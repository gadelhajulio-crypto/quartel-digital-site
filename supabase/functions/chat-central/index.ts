// RCC Wave 1 — Chat Central
// Cérebro institucional: valida HMAC, orquestra resposta do instrutor.
// Nunca escreve tabelas. Nunca emite C5. Nunca decide unread.
// SDK OpenAI removido — fetch direto garante OpenAI-Beta: assistants=v2 em todas as chamadas.
//
// Wave 5c — otimizações de latência:
//   1. create-thread-and-run: 3 chamadas HTTP → 1 (economiza ~500–700ms)
//   2. polling adaptativo: 500ms (early) → 1000ms (late) (economiza ~avg 250ms)
//   3. timing logs por etapa para diagnóstico em produção
//
// Wave 5c-2 — otimizações de infra:
//   4. initial_poll_delay_ms = 1500: espera 1.5s antes do primeiro poll.
//      Racional: produção mostra primeira poll sempre "queued" (modelo não iniciou).
//      Eliminar 2–3 polls wasted × ~150ms RTT = ~300–450ms economizados.
//      Se o modelo completar em < 1.5s: impossível em produção (mínimo ~3s observado).
//
// Wave 5d — estabilidade institucional:
//   5. Retry inteligente: max 2 retries para 429/5xx/network com backoff 500ms→1000ms.
//      NÃO retry em 4xx cliente (prompt inválido, auth).
//   6. Circuit breaker leve: in-memory por isolate, janela 60s, threshold 3 falhas.
//      Após abertura: 30s de quarentena → resposta fallback institucional.
//   7. Token & cost observability: log de prompt_tokens, completion_tokens,
//      total_tokens, estimated_cost_usd, model — sem persistir conteúdo.

const MAX_SKEW_SECONDS = 300;
const OPENAI_API_BASE  = "https://api.openai.com/v1";

// Fallback institucional quando circuit breaker está aberto.
const FALLBACK_REPLY =
  "Serviço de instrução temporariamente indisponível. " +
  "Aguarde alguns instantes e tente novamente.";

const FORCE_AGENTS: Record<string, string> = {
  marinha:     "asst_6TFPlmsULj3fpxArwlkO16nL",
  exercito:    "asst_PL5I6dwKRvHuw6cyy2cNVXHp",
  aeronautica: "asst_0FpXW9zHkPDVBoIuL5fRi6hX",
};

// ── Circuit breaker (Wave 5d) ─────────────────────────────────────────────────
// Estado in-memory por isolate Deno. Supabase reutiliza isolates entre requests
// na mesma região — CB reduz pressão em cascata quando OpenAI degrada.
// Soft circuit breaker: não persiste entre cold starts (sem Redis externo).

const CB_WINDOW_MS = 60_000; // janela rolling de 1 minuto
const CB_THRESHOLD = 3;      // ≥3 falhas na janela → abrir circuito
const CB_OPEN_MS   = 30_000; // manter aberto por 30s; após isso: half-open

const _cb = { failures: 0, windowStart: 0, openedAt: 0 };

function cbIsOpen(request_id: string): boolean {
  const now = Date.now();
  if (now - _cb.windowStart > CB_WINDOW_MS) {
    _cb.failures = 0; _cb.windowStart = now; _cb.openedAt = 0;
  }
  if (_cb.failures >= CB_THRESHOLD) {
    if (now - _cb.openedAt < CB_OPEN_MS) {
      console.warn("[CHAT_CENTRAL_W1] circuit_breaker_open", {
        request_id, failures: _cb.failures,
        open_age_ms: now - _cb.openedAt,
      });
      return true;
    }
    // half-open: permite uma probe request; zera falhas
    console.log("[CHAT_CENTRAL_W1] circuit_breaker_half_open", {
      request_id, failures: _cb.failures,
    });
    _cb.failures = 0; _cb.openedAt = 0;
  }
  return false;
}

function cbRecordFailure(request_id: string): void {
  const now = Date.now();
  if (now - _cb.windowStart > CB_WINDOW_MS) {
    _cb.failures = 0; _cb.windowStart = now;
  }
  _cb.failures++;
  if (_cb.failures >= CB_THRESHOLD && _cb.openedAt === 0) {
    _cb.openedAt = now;
    console.warn("[CHAT_CENTRAL_W1] circuit_breaker_tripped", {
      request_id, failures: _cb.failures,
    });
  }
}

function cbRecordSuccess(): void {
  _cb.failures = 0; _cb.openedAt = 0;
}

// ── Retry (Wave 5d) ───────────────────────────────────────────────────────────
// Retryable: 429 rate limit, 5xx server error, network error (fetch throws).
// NÃO retryable: 4xx (prompt inválido, auth, bad request).

const RETRY_MAX     = 2;
const RETRY_BASE_MS = 500;

function isRetryableOpenAIError(err: unknown): boolean {
  const status = (err as any)?.openai_status ?? 0;
  return status === 0 || status === 429 || status >= 500;
}

async function withOpenAIRetry<T>(
  fn: () => Promise<T>,
  label: string,
  request_id: string,
): Promise<T> {
  let lastErr: unknown;
  for (let attempt = 0; attempt <= RETRY_MAX; attempt++) {
    if (attempt > 0) {
      const delay_ms = RETRY_BASE_MS * (2 ** (attempt - 1)); // 500ms, 1000ms
      console.warn("[CHAT_CENTRAL_W1] openai_retry", {
        request_id, label, attempt, delay_ms,
        status: (lastErr as any)?.openai_status ?? 0,
      });
      await new Promise((r) => setTimeout(r, delay_ms));
    }
    try {
      const result = await fn();
      if (attempt > 0) {
        console.log("[CHAT_CENTRAL_W1] openai_retry_succeeded", {
          request_id, label, attempt,
        });
        cbRecordSuccess();
      }
      return result;
    } catch (err) {
      lastErr = err;
      if (!isRetryableOpenAIError(err)) throw err; // propagar imediatamente
      cbRecordFailure(request_id);
    }
  }
  throw lastErr;
}

// ── Token cost estimation (Wave 5d) ───────────────────────────────────────────
// Preços USD por token (aproximados, maio 2025). Apenas para observabilidade —
// não usar para faturamento. Fallback para gpt-4o quando modelo desconhecido.

const COST_RATES: Record<string, { input: number; output: number }> = {
  "gpt-4o":        { input: 2.50e-6, output: 10.00e-6 },
  "gpt-4o-mini":   { input: 0.15e-6, output:  0.60e-6 },
  "gpt-4-turbo":   { input: 10.0e-6, output: 30.00e-6 },
  "gpt-4":         { input: 30.0e-6, output: 60.00e-6 },
  "gpt-3.5-turbo": { input: 0.50e-6, output:  1.50e-6 },
};

function estimateCostUsd(model: string, promptTokens: number, completionTokens: number): number {
  const r = COST_RATES[model] ?? COST_RATES["gpt-4o"];
  return promptTokens * r.input + completionTokens * r.output;
}

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

// ── OpenAI fetch helpers ───────────────────────────────────────────────────────

function makeOpenAIHeaders(apiKey: string): Record<string, string> {
  return {
    "Authorization":  `Bearer ${apiKey}`,
    "Content-Type":   "application/json",
    "OpenAI-Beta":    "assistants=v2",
  };
}

async function openAIPost(
  path: string,
  apiKey: string,
  body: unknown,
  request_id: string,
  label: string,
): Promise<unknown> {
  const url = `${OPENAI_API_BASE}${path}`;
  const res = await fetch(url, {
    method: "POST",
    headers: makeOpenAIHeaders(apiKey),
    body: JSON.stringify(body),
  });

  const data = await res.json();

  if (!res.ok) {
    console.error("[CHAT_CENTRAL_W1] openai_fetch_error", {
      request_id,
      label,
      http_status:   res.status,
      error_type:    data?.error?.type    ?? null,
      error_code:    data?.error?.code    ?? null,
      error_message: data?.error?.message ?? null,
    });
    const err = new Error(`openai_fetch_failed:${label}:${res.status}`);
    (err as any).openai_status  = res.status;
    (err as any).openai_type    = data?.error?.type    ?? null;
    (err as any).openai_code    = data?.error?.code    ?? null;
    (err as any).openai_message = data?.error?.message ?? null;
    throw err;
  }

  return data;
}

async function openAIGet(
  path: string,
  apiKey: string,
  request_id: string,
  label: string,
): Promise<unknown> {
  const url = `${OPENAI_API_BASE}${path}`;
  const res = await fetch(url, {
    method: "GET",
    headers: makeOpenAIHeaders(apiKey),
  });

  const data = await res.json();

  if (!res.ok) {
    console.error("[CHAT_CENTRAL_W1] openai_fetch_error", {
      request_id,
      label,
      http_status:   res.status,
      error_type:    data?.error?.type    ?? null,
      error_code:    data?.error?.code    ?? null,
      error_message: data?.error?.message ?? null,
    });
    const err = new Error(`openai_fetch_failed:${label}:${res.status}`);
    (err as any).openai_status  = res.status;
    (err as any).openai_type    = data?.error?.type    ?? null;
    (err as any).openai_code    = data?.error?.code    ?? null;
    (err as any).openai_message = data?.error?.message ?? null;
    throw err;
  }

  return data;
}

// ── Polling do run ─────────────────────────────────────────────────────────────
//
// Wave 5c: polling adaptativo — 500ms nos primeiros 8 attempts, depois 1000ms.
// Racional: modelo OpenAI completa tipicamente em 3–8s. Polling a 500ms reduz
// a janela de detecção de 0–1000ms para 0–500ms (economiza avg ~250ms).
// Após 4s de espera (8 polls × 500ms) a resposta demora mais — sem ganho em
// polling curto, então voltamos a 1000ms para não desperdiçar rate limit.
//
// Wave 5c-2: 1500ms de espera inicial antes do primeiro poll.
// Produção mostra que o primeiro poll é sempre "queued" (modelo não iniciou).
// Economiza 2–3 round-trips desnecessários (~300–450ms).

const INITIAL_POLL_DELAY_MS = 1500;

function pollIntervalMs(attempt: number): number {
  return attempt < 8 ? 500 : 1000;
}

async function waitForRunReply(
  apiKey: string,
  threadId: string,
  runId: string,
  request_id: string,
  started: number,
  agentLabel?: string,
): Promise<string> {
  const MAX_ATTEMPTS = 35; // 8×500ms + 27×1000ms = 31s max

  // Wave 5c-2: espera inicial antes do primeiro poll.
  // Produção: modelos levam ~3s mínimo. Pular polls "queued" economiza RTTs.
  console.log("[CHAT_CENTRAL_W1] poll_wait_start", {
    request_id,
    delay_ms: INITIAL_POLL_DELAY_MS,
    ms: Date.now() - started,
  });
  await new Promise((r) => setTimeout(r, INITIAL_POLL_DELAY_MS));
  console.log("[CHAT_CENTRAL_W1] poll_wait_done", {
    request_id,
    ms: Date.now() - started,
  });

  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const t_poll_start = Date.now();

    // Wave 5d: retry para 429/5xx/network — NÃO retry para 4xx (run inválido).
    const run = await withOpenAIRetry(
      () => openAIGet(
        `/threads/${threadId}/runs/${runId}`,
        apiKey,
        request_id,
        "runs.retrieve",
      ),
      "runs.retrieve",
      request_id,
    ) as {
      status: string;
      model?: string;
      usage?: { prompt_tokens: number; completion_tokens: number; total_tokens: number };
      last_error?: { code?: string; message?: string };
    };

    console.log("[CHAT_CENTRAL_W1] step_poll", {
      request_id,
      attempt,
      run_status: run.status,
      ms_poll: Date.now() - t_poll_start,
      ms: Date.now() - started,
    });

    if (run.status === "completed") {
      // Wave 5d: log de token usage e custo estimado por request.
      if (run.usage && run.model) {
        const cost = estimateCostUsd(run.model, run.usage.prompt_tokens, run.usage.completion_tokens);
        console.log("[CHAT_CENTRAL_W1] token_usage", {
          request_id,
          model:               run.model,
          force_agent:         agentLabel ?? "unknown",
          prompt_tokens:       run.usage.prompt_tokens,
          completion_tokens:   run.usage.completion_tokens,
          total_tokens:        run.usage.total_tokens,
          estimated_cost_usd:  parseFloat(cost.toFixed(6)),
          ms:                  Date.now() - started,
        });
      }

      const t_msgs_start = Date.now();
      const msgs = await withOpenAIRetry(
        () => openAIGet(
          `/threads/${threadId}/messages?limit=1&order=desc`,
          apiKey,
          request_id,
          "messages.list",
        ),
        "messages.list",
        request_id,
      ) as { data: Array<{ role: string; content: Array<{ type: string; text?: { value: string } }> }> };

      console.log("[CHAT_CENTRAL_W1] step_messages_list", {
        request_id,
        ms_messages_list: Date.now() - t_msgs_start,
        ms: Date.now() - started,
      });

      const last = msgs.data[0];
      if (last?.role === "assistant" && last.content[0]?.type === "text") {
        return last.content[0].text!.value;
      }
      return "Sem resposta disponível.";
    }

    if (
      run.status === "failed" ||
      run.status === "cancelled" ||
      run.status === "expired"
    ) {
      const lastError = run.last_error ?? null;
      console.error("[CHAT_CENTRAL_W1] openai_run_failed", {
        request_id,
        run_status: run.status,
        run_id:     runId,
        last_error_code:    lastError?.code    ?? null,
        last_error_message: lastError?.message ?? null,
        ms: Date.now() - started,
      });
      cbRecordFailure(request_id);
      throw new Error(`run_ended:${run.status}:${lastError?.code ?? "unknown"}`);
    }

    await new Promise((r) => setTimeout(r, pollIntervalMs(attempt)));
  }

  console.error("[CHAT_CENTRAL_W1] openai_run_timeout", {
    request_id,
    run_id:   runId,
    attempts: MAX_ATTEMPTS,
    ms: Date.now() - started,
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
      method:  req.method,
      has_ts:  !!timestamp,
      has_sig: !!signatureHeader,
    });

    if (!timestamp || !signatureHeader) {
      return json(401, { ok: false, reason: "missing_headers", request_id });
    }

    const ts = Number(timestamp);
    if (!Number.isFinite(ts)) {
      return json(401, { ok: false, reason: "bad_timestamp", request_id });
    }

    const now = Math.floor(Date.now() / 1000);
    const skew = Math.abs(now - ts);
    if (skew > MAX_SKEW_SECONDS) {
      console.warn("[CHAT_CENTRAL_W1] hmac_failed", {
        request_id, reason: "timestamp_skew", skew, ts, now,
      });
      return json(401, { ok: false, reason: "timestamp_skew", request_id });
    }

    const prefix = "sha256=";
    if (!signatureHeader.startsWith(prefix)) {
      console.warn("[CHAT_CENTRAL_W1] hmac_failed", {
        request_id, reason: "bad_signature_format",
      });
      return json(401, { ok: false, reason: "bad_signature_format", request_id });
    }

    const providedHex = signatureHeader.slice(prefix.length).trim().toLowerCase();
    if (!/^[0-9a-f]{64}$/.test(providedHex)) {
      console.warn("[CHAT_CENTRAL_W1] hmac_failed", {
        request_id, reason: "bad_signature_hex", providedLen: providedHex.length,
      });
      return json(401, { ok: false, reason: "bad_signature_hex", request_id });
    }

    const rawBody = await req.text();
    const base = `${ts}.${rawBody}`;
    const expectedHex = await hmacSha256Hex(secret, base);
    const sigOk = timingSafeEqual(hexToBytes(expectedHex), hexToBytes(providedHex));

    if (!sigOk) {
      console.warn("[CHAT_CENTRAL_W1] hmac_failed", {
        request_id,
        reason:         "sig_mismatch",
        ts,
        rawBodyLen:     rawBody.length,
        expectedPrefix: expectedHex.slice(0, 12),
        providedPrefix: providedHex.slice(0, 12),
        ms:             Date.now() - started,
      });
      return json(401, { ok: false, reason: "sig_mismatch", request_id });
    }

    // ── [CHAT_CENTRAL_W1] hmac_ok ────────────────────────────────────────────
    console.log("[CHAT_CENTRAL_W1] hmac_ok", {
      request_id, ts, rawBodyLen: rawBody.length, ms: Date.now() - started,
    });

    let payload: {
      recruta_id:    string;
      instrutor_slug: string;
      forca:         string;
      access_mode:   string;
      user_text:     string;
      session_id:    string;
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

    const agentId = FORCE_AGENTS[forca] ?? FORCE_AGENTS.marinha;
    const additionalInstructions = buildAdditionalInstructions(instrutor_slug, forca, access_mode);
    const correlation_id = crypto.randomUUID();

    // ── Wave 5d: circuit breaker check ───────────────────────────────────────
    // Se o circuito estiver aberto (OpenAI degradado), retornar fallback imediato
    // sem saturar a fila de retries. Estado reset após CB_OPEN_MS (30s).
    if (cbIsOpen(request_id)) {
      console.warn("[CHAT_CENTRAL_W1] circuit_breaker_fallback", {
        request_id, correlation_id, forca, ms: Date.now() - started,
      });
      return json(200, {
        ok: true,
        reply: FALLBACK_REPLY,
        degraded: true,
        correlation_id,
        request_id,
        ms: Date.now() - started,
      });
    }

    // ── [CHAT_CENTRAL_W1] openai_start ───────────────────────────────────────
    console.log("[CHAT_CENTRAL_W1] openai_start", {
      request_id,
      correlation_id,
      instrutor_slug,
      forca,
      access_mode,
      ms: Date.now() - started,
    });

    // Wave 5c: create-thread-and-run em UMA única chamada HTTP.
    // Antes: POST /threads + POST /threads/:id/messages + POST /threads/:id/runs = 3 calls (~500–700ms).
    // Agora: POST /threads/runs com thread embutido = 1 call (~200–350ms).
    // Ref: https://platform.openai.com/docs/api-reference/runs/createThreadAndRun
    //
    // Wave 5d: wrapped em withOpenAIRetry para 429/5xx/network (max 2 retries).
    const t_create = Date.now();
    const threadAndRun = await withOpenAIRetry(
      () => openAIPost(
        "/threads/runs",
        openaiKey,
        {
          assistant_id:            agentId,
          additional_instructions: additionalInstructions,
          thread: {
            messages: [{ role: "user", content: user_text }],
          },
        },
        request_id,
        "threads.create_and_run",
      ),
      "threads.create_and_run",
      request_id,
    ) as { id: string; thread_id: string };

    console.log("[CHAT_CENTRAL_W1] step_create_thread_and_run", {
      request_id,
      thread_id: threadAndRun.thread_id,
      run_id:    threadAndRun.id,
      ms_create: Date.now() - t_create,
      ms:        Date.now() - started,
    });

    // Aguardar conclusão do run e recuperar resposta.
    // Wave 5d: agentLabel = forca para token_usage log.
    const reply = await waitForRunReply(
      openaiKey,
      threadAndRun.thread_id,
      threadAndRun.id,
      request_id,
      started,
      forca,
    );

    // Wave 5d: sucesso → reset circuit breaker
    cbRecordSuccess();

    // ── [CHAT_CENTRAL_W1] openai_success ─────────────────────────────────────
    console.log("[CHAT_CENTRAL_W1] openai_success", {
      request_id,
      correlation_id,
      replyLen: reply.length,
      ms:       Date.now() - started,
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
    let reason = "internal_error";
    let isOpenAIFailure = false;
    if (errStr.includes("run_ended:"))           { reason = errStr.replace("Error: ", "").split(":").slice(0, 2).join(":"); isOpenAIFailure = true; }
    else if (errStr.includes("run_timeout"))     { reason = "openai_run_timeout"; isOpenAIFailure = true; }
    else if (errStr.includes("openai_fetch_failed")) { reason = "openai_error"; isOpenAIFailure = true; }
    else if (errStr.toLowerCase().includes("openai")) { reason = "openai_error"; isOpenAIFailure = true; }

    // Wave 5d: falhas OpenAI não capturadas pelo retry também contam no CB
    // (ex: run_timeout após MAX_ATTEMPTS, run_ended:failed)
    if (isOpenAIFailure) cbRecordFailure(request_id);

    console.error("[CHAT_CENTRAL_W1] exception", {
      request_id,
      reason,
      err:                errStr,
      openai_http_status: (err as any)?.openai_status  ?? null,
      openai_error_type:  (err as any)?.openai_type    ?? null,
      openai_error_code:  (err as any)?.openai_code    ?? null,
      openai_message:     (err as any)?.openai_message ?? null,
      ms:                 Date.now() - started,
    });
    return json(500, { ok: false, reason, request_id });
  }
});
