// RCC Wave 1 — Chat Central
// Cérebro institucional: valida HMAC, orquestra resposta do instrutor.
// Nunca escreve tabelas. Nunca emite C5. Nunca decide unread.

import { OpenAI } from "./deps.ts";

const MAX_SKEW_SECONDS = 300;

const FORCE_AGENTS: Record<string, string> = {
  marinha:     "asst_6TFPlmsULj3fpxArwlkO16nL",
  exercito:    "asst_PL5I6dwKRvHuw6cyy2cNVXHp",
  aeronautica: "asst_0FpXW9zHkPDVBoIuL5fRi6hX",
};

const PERSONALITY_INSTRUCTIONS: Record<string, string> = {
  objetivo:    "Tom direto, disciplinado e objetivo. Vá ao ponto sem rodeios.",
  estrategico: "Tom analítico e estratégico. Explique o raciocínio e o contexto antes de responder.",
  didatico:    "Tom claro, paciente e educativo. Use exemplos concretos quando ajudar na compreensão.",
};

function buildAdditionalInstructions(
  instrutor_slug: string,
  forca: string,
  access_mode: string,
): string {
  const personality =
    PERSONALITY_INSTRUCTIONS[instrutor_slug] ?? PERSONALITY_INSTRUCTIONS.objetivo;
  const isRestricted = access_mode === "restricted";

  return [
    `PERSONALIDADE: ${personality}`,
    `FORÇA: ${forca.toUpperCase()}`,
    isRestricted
      ? "ESCOPO RESTRITO: Responda apenas sobre conteúdos disponíveis na degustação. Para aprofundamento, oriente o recruta a adquirir o acesso completo de forma institucional e objetiva."
      : "",
    "INSTRUÇÕES FIXAS: Mantenha linguagem institucional. Não use emojis. Não invente informações. Seja preciso.",
  ].filter(Boolean).join("\n");
}

async function waitForRunReply(
  openai: OpenAI,
  threadId: string,
  runId: string,
  request_id: string,
): Promise<string> {
  const MAX_ATTEMPTS = 25;
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const run = await openai.beta.threads.runs.retrieve(threadId, runId);

    if (run.status === "completed") {
      const msgs = await openai.beta.threads.messages.list(threadId, { limit: 1 });
      const last = msgs.data[0];
      if (last?.role === "assistant" && last.content[0]?.type === "text") {
        return last.content[0].text.value;
      }
      return "Sem resposta disponível.";
    }

    if (
      run.status === "failed" ||
      run.status === "cancelled" ||
      run.status === "expired"
    ) {
      const lastError = (run as any).last_error ?? null;
      console.error("[CHAT_CENTRAL_W1] openai_run_failed", {
        request_id,
        run_status: run.status,
        run_id: runId,
        last_error_code: lastError?.code ?? null,
        last_error_message: lastError?.message ?? null,
      });
      throw new Error(`run_ended:${run.status}:${lastError?.code ?? "unknown"}`);
    }

    await new Promise((r) => setTimeout(r, 1000));
  }
  console.error("[CHAT_CENTRAL_W1] openai_run_timeout", {
    request_id,
    run_id: runId,
    attempts: MAX_ATTEMPTS,
  });
  throw new Error("run_timeout");
}

// ── HMAC helpers ──────────────────────────────────────────────────────────────

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

function timingSafeEqual(a: Uint8Array, b: Uint8Array) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

function hexToBytes(hex: string) {
  if (hex.length % 2 !== 0) throw new Error("bad_hex_length");
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

function bytesToHex(bytes: Uint8Array) {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Verifica HMAC de `${timestamp_number}.${rawBody}` — mesmo contrato de instrutor-send.
async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sigBuf = await crypto.subtle.sign("HMAC", key, enc.encode(message));
  return bytesToHex(new Uint8Array(sigBuf));
}

// ── Handler principal ─────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  const request_id = crypto.randomUUID();
  const started = Date.now();

  try {
    const secret = Deno.env.get("QD_HMAC_SECRET");
    if (!secret) {
      console.error("[CHAT_CENTRAL_W1] missing_secret", { request_id });
      return json(500, { ok: false, reason: "missing_secret", request_id });
    }

    // ── [CHAT_CENTRAL_W1] start ───────────────────────────────────────────────
    const timestamp = req.headers.get("x-qd-timestamp");
    const signatureHeader = req.headers.get("x-qd-signature");

    console.log("[CHAT_CENTRAL_W1] start", {
      request_id,
      method: req.method,
      has_ts: !!timestamp,
      has_sig: !!signatureHeader,
    });

    if (!timestamp || !signatureHeader) {
      return json(401, { ok: false, reason: "missing_headers", request_id });
    }

    // ts como número — ${ts} em template literal produz a mesma string que o
    // instrutor-send envia como header x-qd-timestamp.
    const ts = Number(timestamp);
    if (!Number.isFinite(ts)) {
      return json(401, { ok: false, reason: "bad_timestamp", request_id });
    }

    const now = Math.floor(Date.now() / 1000);
    const skew = Math.abs(now - ts);
    if (skew > MAX_SKEW_SECONDS) {
      console.warn("[CHAT_CENTRAL_W1] hmac_failed", {
        request_id,
        reason: "timestamp_skew",
        skew,
        ts,
        now,
      });
      return json(401, { ok: false, reason: "timestamp_skew", request_id });
    }

    const prefix = "sha256=";
    if (!signatureHeader.startsWith(prefix)) {
      console.warn("[CHAT_CENTRAL_W1] hmac_failed", {
        request_id,
        reason: "bad_signature_format",
      });
      return json(401, { ok: false, reason: "bad_signature_format", request_id });
    }

    const providedHex = signatureHeader.slice(prefix.length).trim().toLowerCase();
    if (!/^[0-9a-f]{64}$/.test(providedHex)) {
      console.warn("[CHAT_CENTRAL_W1] hmac_failed", {
        request_id,
        reason: "bad_signature_hex",
        providedLen: providedHex.length,
      });
      return json(401, { ok: false, reason: "bad_signature_hex", request_id });
    }

    // rawBody: string exato recebido no body HTTP.
    // base: `${ts}.${rawBody}` — exatamente o que instrutor-send assinou.
    const rawBody = await req.text();
    const base = `${ts}.${rawBody}`;
    const expectedHex = await hmacSha256Hex(secret, base);

    const sigOk = timingSafeEqual(hexToBytes(expectedHex), hexToBytes(providedHex));

    if (!sigOk) {
      // ── [CHAT_CENTRAL_W1] hmac_failed ───────────────────────────────────────
      console.warn("[CHAT_CENTRAL_W1] hmac_failed", {
        request_id,
        reason: "sig_mismatch",
        ts,
        rawBodyLen: rawBody.length,
        expectedPrefix: expectedHex.slice(0, 12),
        providedPrefix: providedHex.slice(0, 12),
        ms: Date.now() - started,
      });
      return json(401, { ok: false, reason: "sig_mismatch", request_id });
    }

    // ── [CHAT_CENTRAL_W1] hmac_ok ────────────────────────────────────────────
    console.log("[CHAT_CENTRAL_W1] hmac_ok", {
      request_id,
      ts,
      rawBodyLen: rawBody.length,
      ms: Date.now() - started,
    });

    let payload: {
      recruta_id: string;
      instrutor_slug: string;
      forca: string;
      access_mode: string;
      user_text: string;
      session_id: string;
    };

    try {
      payload = JSON.parse(rawBody);
    } catch {
      return json(400, { ok: false, reason: "invalid_json", request_id });
    }

    const { instrutor_slug, forca, access_mode, user_text, recruta_id } = payload;

    if (!user_text || !instrutor_slug || !forca || !recruta_id) {
      return json(400, { ok: false, reason: "missing_fields", request_id });
    }

    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) {
      console.error("[CHAT_CENTRAL_W1] missing_openai_key", { request_id });
      return json(500, { ok: false, reason: "missing_openai_key", request_id });
    }

    const openai = new OpenAI({ apiKey: openaiKey });
    const agentId = FORCE_AGENTS[forca] ?? FORCE_AGENTS.marinha;
    const additionalInstructions = buildAdditionalInstructions(instrutor_slug, forca, access_mode);
    const correlation_id = crypto.randomUUID();

    // ── [CHAT_CENTRAL_W1] openai_start ───────────────────────────────────────
    console.log("[CHAT_CENTRAL_W1] openai_start", {
      request_id,
      correlation_id,
      instrutor_slug,
      forca,
      access_mode,
      agentId,
      ms: Date.now() - started,
    });

    const thread = await openai.beta.threads.create();
    await openai.beta.threads.messages.create(thread.id, {
      role: "user",
      content: user_text,
    });

    const run = await openai.beta.threads.runs.create(thread.id, {
      assistant_id: agentId,
      additional_instructions: additionalInstructions,
    });

    const reply = await waitForRunReply(openai, thread.id, run.id, request_id);

    // ── [CHAT_CENTRAL_W1] openai_success ─────────────────────────────────────
    console.log("[CHAT_CENTRAL_W1] openai_success", {
      request_id,
      correlation_id,
      replyLen: reply.length,
      ms: Date.now() - started,
    });

    return json(200, {
      ok: true,
      reply,
      correlation_id,
      request_id,
      ms: Date.now() - started,
    });
  } catch (err) {
    const errStr = String(err);
    // Extrair reason do erro para facilitar diagnóstico no instrutor-send
    let reason = "internal_error";
    if (errStr.includes("run_ended:")) reason = errStr.replace("Error: ", "").split(":").slice(0, 2).join(":");
    else if (errStr.includes("run_timeout")) reason = "openai_run_timeout";
    else if (errStr.includes("openai") || errStr.includes("OpenAI")) reason = "openai_error";

    console.error("[CHAT_CENTRAL_W1] exception", {
      request_id,
      err: errStr,
      reason,
      ms: Date.now() - started,
    });
    return json(500, { ok: false, reason, request_id });
  }
});
