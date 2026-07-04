// RCC Wave 1 — Chat Central
// Cérebro institucional: valida HMAC, orquestra resposta do instrutor.
// Nunca escreve tabelas. Nunca emite C5. Nunca decide unread.
// SDK OpenAI removido — fetch direto via Responses API.
//
// Wave 5f — Responses API + SSE streaming:
//   Elimina: thread lifecycle / polling / messages.list / create_thread_and_run.
//   Substitui por: POST /v1/responses (stream:true ou stream:false).
//   Modo streaming: retorna text/event-stream com eventos delta e done.
//   Modo JSON (stream:false ou ausente): retorna JSON com reply (backward compat).
//   PERSONA_INSTRUCTIONS inline substituem PERSONA_AGENTS (assistant IDs).
//
// Waves 5c–5e mantidas: circuit breaker, retry, cost observability, material scope.
//
// INVARIANTES:
//   - Nunca persistir conteúdo de mensagens
//   - Nunca emitir eventos C5
//   - HMAC validado antes de qualquer processamento
//   - Circuit breaker protege contra cascata de falhas OpenAI

const MAX_SKEW_SECONDS  = 300;
const OPENAI_API_BASE   = "https://api.openai.com/v1";
const RESPONSES_MODEL   = "gpt-4o";
const MAX_OUTPUT_TOKENS = 1024;

// Resposta de fallback quando circuit breaker está aberto.
const FALLBACK_REPLY =
  "Serviço de instrução temporariamente indisponível. " +
  "Aguarde alguns instantes e tente novamente.";

// Wave 5f: system prompts inline por persona (substituem PERSONA_AGENTS assistant IDs).
// Cada persona define personalidade; força/material vêm de buildAdditionalInstructions,
// que é appended ao campo instructions da Responses API.
//
// NOTA: conteúdo alinhado com personalidades dos assistants objetivo/estrategico/didatico.
// Se os prompts precisarem ser ajustados, editar aqui e re-deployar chat-central.
const PERSONA_INSTRUCTIONS: Record<string, string> = {
  objetivo: [
    "Você é o Sargento Ramos, instrutor institucional do Quartel Digital.",
    "Personalidade: direto, disciplinado, objetivo. Respostas concisas e assertivas — sem rodeios.",
    "Idioma: Português do Brasil. Tom: militar, formal.",
    "Responda apenas sobre o material autorizado indicado em MATERIAL AUTORIZADO.",
    "Para temas fora do material: oriente o recruta a verificar o regulamento correspondente.",
  ].join("\n"),

  estrategico: [
    "Você é o Sargento Rocha, instrutor institucional do Quartel Digital.",
    "Personalidade: analítico, estratégico, metódico. Visão sistêmica das normas e regulamentos.",
    "Idioma: Português do Brasil. Tom: militar, formal.",
    "Aprofunde contexto regulatório, implicações e consequências das normas quando pertinente.",
    "Responda apenas sobre o material autorizado indicado em MATERIAL AUTORIZADO.",
  ].join("\n"),

  didatico: [
    "Você é a Sargento Sara, instrutora institucional do Quartel Digital.",
    "Personalidade: clara, educativa, paciente. Facilita o aprendizado progressivo do regulamento.",
    "Idioma: Português do Brasil. Tom: militar, formal mas acessível.",
    "Use exemplos concretos e estruture as respostas para facilitar a compreensão.",
    "Responda apenas sobre o material autorizado indicado em MATERIAL AUTORIZADO.",
  ].join("\n"),
};

// ── Circuit breaker (Wave 5d) ─────────────────────────────────────────────────
// Estado in-memory por isolate Deno. Soft circuit breaker sem Redis externo.

const CB_WINDOW_MS = 60_000;
const CB_THRESHOLD = 3;
const CB_OPEN_MS   = 30_000;
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
// NÃO retryable: 4xx cliente.

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
      const delay_ms = RETRY_BASE_MS * (2 ** (attempt - 1));
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
      if (!isRetryableOpenAIError(err)) throw err;
      cbRecordFailure(request_id);
    }
  }
  throw lastErr;
}

// ── Token cost estimation (Wave 5d) ───────────────────────────────────────────
// Wave 5f: usa input_tokens/output_tokens (Responses API) em vez de
// prompt_tokens/completion_tokens (Assistants API). Rates idênticos.

const COST_RATES: Record<string, { input: number; output: number }> = {
  "gpt-4o":        { input: 2.50e-6, output: 10.00e-6 },
  "gpt-4o-mini":   { input: 0.15e-6, output:  0.60e-6 },
  "gpt-4-turbo":   { input: 10.0e-6, output: 30.00e-6 },
  "gpt-4":         { input: 30.0e-6, output: 60.00e-6 },
  "gpt-3.5-turbo": { input: 0.50e-6, output:  1.50e-6 },
};

function estimateCostUsd(model: string, inputTokens: number, outputTokens: number): number {
  const r = COST_RATES[model] ?? COST_RATES["gpt-4o"];
  return inputTokens * r.input + outputTokens * r.output;
}

// ── Material scope por força (Wave 5e-3) ──────────────────────────────────────
// Marinha: currículo real (10 módulos, ~58 aulas).
// Exército / Aeronáutica: placeholder controlado (currículo não desenvolvido).

const MATERIAL_SCOPE: Record<string, { full: string; degustacao: string }> = {
  marinha: {
    full: [
      "Regulamento Disciplinar para a Marinha (RDM)",
      "Instrução Militar Naval: Estatuto dos Militares, Cerimonial, Uniformes, Ordenança",
      "Higiene e Primeiros Socorros",
      "Noções de Armamento: armamento leve, munição naval",
      "Combate a Incêndio a bordo",
      "Organização Básica da Marinha do Brasil",
      "Comunicações Navais",
      "Tradições e Fatos da Marinha do Brasil",
      "Serviço Geral de Taifa",
      "Documentos Administrativos",
    ].join(" • "),
    degustacao: "RDM: Fundamentos, Contravenção Disciplinar, Natureza das Contravenções",
  },
  exercito: {
    full:       "Regulamento Disciplinar do Exército (RDE) e material complementar do Exército Brasileiro",
    degustacao: "Introdução ao Regulamento Disciplinar do Exército (RDE)",
  },
  aeronautica: {
    full:       "Regulamento Disciplinar da Aeronáutica (RDA) e material complementar da Força Aérea Brasileira",
    degustacao: "Introdução ao Regulamento Disciplinar da Aeronáutica (RDA)",
  },
};

function buildAdditionalInstructions(forca: string, access_mode: string): string {
  const scope = MATERIAL_SCOPE[forca] ?? MATERIAL_SCOPE.marinha;
  const isRestricted = access_mode === "restricted";
  const materialAtivo = isRestricted ? scope.degustacao : scope.full;
  return [
    `FORÇA ATIVA: ${forca.toUpperCase()}`,
    `MATERIAL AUTORIZADO: ${materialAtivo}`,
    isRestricted
      ? "ESCOPO: restrito — responder apenas sobre o material de degustação acima; para aprofundamento, orientar sobre acesso completo de forma institucional"
      : "ESCOPO: completo — responder sobre qualquer módulo do material autorizado acima",
  ].join("\n");
}

// ── Responses API — modo não-streaming ────────────────────────────────────────

function makeResponsesHeaders(apiKey: string): Record<string, string> {
  return {
    "Authorization": `Bearer ${apiKey}`,
    "Content-Type":  "application/json",
  };
}

async function callResponsesAPI(
  apiKey: string,
  systemPrompt: string,
  userInput: string,
  request_id: string,
): Promise<{
  text: string;
  model: string;
  input_tokens: number;
  output_tokens: number;
  total_tokens: number;
}> {
  const res = await fetch(`${OPENAI_API_BASE}/responses`, {
    method:  "POST",
    headers: makeResponsesHeaders(apiKey),
    body: JSON.stringify({
      model:             RESPONSES_MODEL,
      instructions:      systemPrompt,
      input:             userInput,
      max_output_tokens: MAX_OUTPUT_TOKENS,
      stream:            false,
    }),
  });

  const data = await res.json() as any;

  if (!res.ok) {
    console.error("[CHAT_CENTRAL_W1] responses_api_error", {
      request_id,
      http_status:   res.status,
      error_type:    data?.error?.type    ?? null,
      error_code:    data?.error?.code    ?? null,
      error_message: data?.error?.message ?? null,
    });
    const err = new Error(`responses_api_failed:${res.status}`);
    (err as any).openai_status  = res.status;
    (err as any).openai_type    = data?.error?.type    ?? null;
    (err as any).openai_code    = data?.error?.code    ?? null;
    (err as any).openai_message = data?.error?.message ?? null;
    throw err;
  }

  const text  = data.output?.[0]?.content?.[0]?.text ?? "Sem resposta disponível.";
  const usage = data.usage ?? {};

  return {
    text,
    model:         data.model ?? RESPONSES_MODEL,
    input_tokens:  usage.input_tokens  ?? 0,
    output_tokens: usage.output_tokens ?? 0,
    total_tokens:  usage.total_tokens  ?? 0,
  };
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
  const started    = Date.now();
  const encoder    = new TextEncoder();

  try {
    const secret = Deno.env.get("QD_HMAC_SECRET");
    if (!secret) {
      console.error("[CHAT_CENTRAL_W1] missing_secret", { request_id });
      return json(500, { ok: false, reason: "missing_secret", request_id });
    }

    const timestamp       = req.headers.get("x-qd-timestamp");
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

    const now  = Math.floor(Date.now() / 1000);
    const skew = Math.abs(now - ts);
    if (skew > MAX_SKEW_SECONDS) {
      console.warn("[CHAT_CENTRAL_W1] hmac_failed", {
        request_id, reason: "timestamp_skew", skew, ts, now,
      });
      return json(401, { ok: false, reason: "timestamp_skew", request_id });
    }

    const prefix = "sha256=";
    if (!signatureHeader.startsWith(prefix)) {
      return json(401, { ok: false, reason: "bad_signature_format", request_id });
    }

    const providedHex = signatureHeader.slice(prefix.length).trim().toLowerCase();
    if (!/^[0-9a-f]{64}$/.test(providedHex)) {
      return json(401, { ok: false, reason: "bad_signature_hex", request_id });
    }

    const rawBody     = await req.text();
    const base        = `${ts}.${rawBody}`;
    const expectedHex = await hmacSha256Hex(secret, base);
    const sigOk       = timingSafeEqual(hexToBytes(expectedHex), hexToBytes(providedHex));

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

    console.log("[CHAT_CENTRAL_W1] hmac_ok", {
      request_id, ts, rawBodyLen: rawBody.length, ms: Date.now() - started,
    });

    let payload: {
      recruta_id:     string;
      instrutor_slug: string;
      forca:          string;
      access_mode:    string;
      user_text:      string;
      session_id:     string;
      stream?:        boolean;
    };

    try {
      payload = JSON.parse(rawBody);
    } catch {
      return json(400, { ok: false, reason: "invalid_json", request_id });
    }

    const { instrutor_slug, forca, access_mode, user_text, recruta_id } = payload;
    const streamMode = payload.stream === true;

    if (!user_text || !instrutor_slug || !forca || !recruta_id) {
      return json(400, { ok: false, reason: "missing_fields", request_id });
    }

    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) {
      console.error("[CHAT_CENTRAL_W1] missing_openai_key", { request_id });
      return json(500, { ok: false, reason: "missing_openai_key", request_id });
    }

    // Wave 5f: routing por persona → PERSONA_INSTRUCTIONS (inline system prompt).
    // Fallback = 'objetivo' (Sgt. Ramos) se slug inválido ou ausente.
    const agentLabel   = instrutor_slug in PERSONA_INSTRUCTIONS ? instrutor_slug : "objetivo";
    const personaInst  = PERSONA_INSTRUCTIONS[agentLabel];
    const materialCtx  = buildAdditionalInstructions(forca, access_mode);
    const systemPrompt = `${personaInst}\n\n${materialCtx}`;
    const correlation_id = crypto.randomUUID();

    console.log("[CHAT_CENTRAL_W1] persona_agent_selected", {
      request_id,
      instrutor_slug,
      agent_label:   agentLabel,
      used_fallback: !(instrutor_slug in PERSONA_INSTRUCTIONS),
      stream_mode:   streamMode,
    });

    console.log("[CHAT_CENTRAL_W1] material_scope_selected", {
      request_id,
      forca,
      access_mode,
      scope_type:        access_mode === "restricted" ? "degustacao" : "full",
      scope_is_real:     forca === "marinha",
      system_prompt_size: systemPrompt.length,
    });

    // ── Circuit breaker check ─────────────────────────────────────────────────
    if (cbIsOpen(request_id)) {
      console.warn("[CHAT_CENTRAL_W1] circuit_breaker_fallback", {
        request_id, correlation_id, forca, ms: Date.now() - started,
      });
      if (streamMode) {
        // Fallback em modo streaming: emitir done com resposta de degradação
        const fallbackStream = new ReadableStream({
          start(ctrl) {
            ctrl.enqueue(encoder.encode(
              `data: ${JSON.stringify({
                type:         "done",
                text:         FALLBACK_REPLY,
                usage:        null,
                correlation_id,
                request_id,
                degraded:     true,
              })}\n\n`
            ));
            ctrl.close();
          },
        });
        return new Response(fallbackStream, {
          status:  200,
          headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache" },
        });
      }
      return json(200, {
        ok: true, reply: FALLBACK_REPLY, degraded: true,
        correlation_id, request_id, ms: Date.now() - started,
      });
    }

    console.log("[CHAT_CENTRAL_W1] openai_start", {
      request_id, correlation_id, instrutor_slug: agentLabel,
      forca, access_mode, stream_mode: streamMode,
      ms: Date.now() - started,
    });

    // ── Modo streaming (Wave 5f) ──────────────────────────────────────────────
    // Chama POST /v1/responses com stream:true.
    // Parseia eventos SSE do OpenAI e re-emite como formato simplificado:
    //   delta: {"type":"delta","delta":"texto parcial"}
    //   done:  {"type":"done","text":"texto completo","usage":{...},...}
    //   error: {"type":"error","reason":"..."}
    if (streamMode) {
      let oaiRes: Response;
      try {
        // Retry na chamada inicial (429/5xx/network). Não retry mid-stream.
        oaiRes = await withOpenAIRetry(
          () => fetch(`${OPENAI_API_BASE}/responses`, {
            method:  "POST",
            headers: makeResponsesHeaders(openaiKey),
            body: JSON.stringify({
              model:             RESPONSES_MODEL,
              instructions:      systemPrompt,
              input:             user_text,
              max_output_tokens: MAX_OUTPUT_TOKENS,
              stream:            true,
            }),
          }).then(async (res) => {
            if (!res.ok) {
              const errData = await res.json().catch(() => ({})) as any;
              const err = new Error(`responses_stream_failed:${res.status}`);
              (err as any).openai_status  = res.status;
              (err as any).openai_type    = errData?.error?.type    ?? null;
              (err as any).openai_code    = errData?.error?.code    ?? null;
              (err as any).openai_message = errData?.error?.message ?? null;
              throw err;
            }
            return res;
          }),
          "responses.stream",
          request_id,
        );
      } catch (streamInitErr) {
        cbRecordFailure(request_id);
        console.error("[CHAT_CENTRAL_W1] responses_stream_init_failed", {
          request_id, err: String(streamInitErr),
          openai_status: (streamInitErr as any)?.openai_status ?? null,
          ms: Date.now() - started,
        });
        return json(502, { ok: false, reason: "openai_stream_unavailable", request_id });
      }

      const oaiReader = oaiRes.body!.getReader();
      const decoder   = new TextDecoder();
      let   sseBuffer  = "";
      let   fullText   = "";
      let   streamDone = false;

      const responseStream = new ReadableStream({
        async start(ctrl) {
          try {
            outer: while (true) {
              const { done, value } = await oaiReader.read();
              if (done) break;

              sseBuffer += decoder.decode(value, { stream: true });
              const events = sseBuffer.split("\n\n");
              sseBuffer = events.pop() ?? "";

              for (const rawEvent of events) {
                if (!rawEvent.trim()) continue;

                let eventName = "";
                let dataLine  = "";
                for (const line of rawEvent.split("\n")) {
                  if (line.startsWith("event: ")) eventName = line.slice(7).trim();
                  if (line.startsWith("data: "))  dataLine  = line.slice(6).trim();
                }
                if (!dataLine || dataLine === "[DONE]") continue;

                try {
                  const parsed = JSON.parse(dataLine) as any;
                  const evType = parsed.type ?? eventName;

                  if (evType === "response.output_text.delta") {
                    const delta = parsed.delta ?? "";
                    if (delta) {
                      fullText += delta;
                      ctrl.enqueue(encoder.encode(
                        `data: ${JSON.stringify({ type: "delta", delta })}\n\n`
                      ));
                    }

                  } else if (evType === "response.completed") {
                    const usage     = parsed.response?.usage ?? null;
                    const finalText = parsed.response?.output?.[0]?.content?.[0]?.text ?? fullText;
                    const model     = parsed.response?.model ?? RESPONSES_MODEL;

                    if (usage) {
                      const cost = estimateCostUsd(
                        model, usage.input_tokens ?? 0, usage.output_tokens ?? 0,
                      );
                      console.log("[CHAT_CENTRAL_W1] token_usage", {
                        request_id, model, force_agent: agentLabel,
                        input_tokens:       usage.input_tokens  ?? 0,
                        output_tokens:      usage.output_tokens ?? 0,
                        total_tokens:       usage.total_tokens  ?? 0,
                        estimated_cost_usd: parseFloat(cost.toFixed(6)),
                        stream_mode:        true,
                        ms:                 Date.now() - started,
                      });
                    }

                    console.log("[CHAT_CENTRAL_W1] openai_success", {
                      request_id, correlation_id, replyLen: finalText.length,
                      stream_mode: true, ms: Date.now() - started,
                    });

                    ctrl.enqueue(encoder.encode(
                      `data: ${JSON.stringify({
                        type: "done",
                        text: finalText,
                        usage,
                        correlation_id,
                        request_id,
                      })}\n\n`
                    ));
                    streamDone = true;
                    cbRecordSuccess();
                    break outer;
                  }
                } catch {
                  // skip malformed SSE event
                }
              }
            }

            // EOF sem evento done (resposta truncada pela OpenAI)
            if (!streamDone && fullText) {
              ctrl.enqueue(encoder.encode(
                `data: ${JSON.stringify({
                  type:         "done",
                  text:         fullText,
                  usage:        null,
                  correlation_id,
                  request_id,
                  truncated:    true,
                })}\n\n`
              ));
              cbRecordSuccess();
            }
          } catch (streamErr) {
            cbRecordFailure(request_id);
            console.error("[CHAT_CENTRAL_W1] streaming_read_error", {
              request_id, err: String(streamErr), ms: Date.now() - started,
            });
            ctrl.enqueue(encoder.encode(
              `data: ${JSON.stringify({ type: "error", reason: "streaming_failed", request_id })}\n\n`
            ));
          } finally {
            ctrl.close();
          }
        },
      });

      return new Response(responseStream, {
        status:  200,
        headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache" },
      });
    }

    // ── Modo JSON — stream:false ou ausente (backward compat) ─────────────────
    const t_openai = Date.now();
    const result = await withOpenAIRetry(
      () => callResponsesAPI(openaiKey, systemPrompt, user_text, request_id),
      "responses.create",
      request_id,
    );

    cbRecordSuccess();

    const cost = estimateCostUsd(result.model, result.input_tokens, result.output_tokens);
    console.log("[CHAT_CENTRAL_W1] token_usage", {
      request_id, model: result.model, force_agent: agentLabel,
      input_tokens:       result.input_tokens,
      output_tokens:      result.output_tokens,
      total_tokens:       result.total_tokens,
      estimated_cost_usd: parseFloat(cost.toFixed(6)),
      stream_mode:        false,
      ms:                 Date.now() - started,
    });

    console.log("[CHAT_CENTRAL_W1] openai_success", {
      request_id, correlation_id, replyLen: result.text.length,
      ms_openai: Date.now() - t_openai, ms: Date.now() - started,
    });

    return json(200, {
      ok: true, reply: result.text, correlation_id, request_id,
      ms: Date.now() - started,
    });

  } catch (err) {
    const errStr = String(err);
    let reason = "internal_error";
    let isOpenAIFailure = false;
    if (errStr.includes("responses_api_failed") || errStr.includes("responses_stream_failed")) {
      reason = "openai_error"; isOpenAIFailure = true;
    } else if (errStr.toLowerCase().includes("openai")) {
      reason = "openai_error"; isOpenAIFailure = true;
    }
    if (isOpenAIFailure) cbRecordFailure(request_id);

    console.error("[CHAT_CENTRAL_W1] exception", {
      request_id, reason, err: errStr,
      openai_http_status: (err as any)?.openai_status  ?? null,
      openai_error_type:  (err as any)?.openai_type    ?? null,
      openai_error_code:  (err as any)?.openai_code    ?? null,
      openai_message:     (err as any)?.openai_message ?? null,
      ms:                 Date.now() - started,
    });
    return json(500, { ok: false, reason, request_id });
  }
});
