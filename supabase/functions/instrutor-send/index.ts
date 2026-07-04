// RCC Wave 1 — Instrutor Send
// Orquestrador: autentica, delega ao Chat Central, persiste via RPC.
// Nunca escreve tabelas diretamente. Nunca emite C5. Nunca decide unread.
//
// Wave 5c-2 — otimização de identidade: sub do JWT extraído em JS (0ms rede)
//   + service_role.from("recrutas") com auth_id filter (~300ms). Sem overhead de view.
//
// Wave 5f — SSE proxy mode + cache:
//   Quando Accept: text/event-stream: chama chat-central com stream:true,
//   proxeia deltas para o cliente, persiste via RPC após done, push em background.
//   Cache (Wave 5g): lookup antes de chat-central, write em background após miss.
//
// Wave 5g — cache institucional:
//   Perguntas elegíveis (<300 chars, <200 tokens, sem pronomes pessoais) são cacheadas.
//   cache_key: instrutor_slug:forca:access_mode:scope_type:model:v1:question_hash.
//   Telemetria: [INSTRUTOR_SEND_CACHE] cache_lookup/hit/miss/write/skipped.

import { createClient } from "supabase";

/**
 * Extrai o claim `sub` do JWT sem verificar assinatura.
 * Usado apenas para obter o auth_id canônico e passar explicitamente ao service_role.
 */
function extractJwtSub(authHeader: string): string | null {
  try {
    const token = authHeader.startsWith("Bearer ")
      ? authHeader.slice(7)
      : authHeader;
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const payload = JSON.parse(atob(b64));
    return typeof payload.sub === "string" ? payload.sub : null;
  } catch {
    return null;
  }
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin":  "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, accept",
};

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      "content-type": "application/json; charset=utf-8",
    },
  });
}

function sseErrorEvent(reason: string): string {
  return `data: ${JSON.stringify({ type: "error", reason })}\n\n`;
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function signHmacSha256(
  secret: string,
  timestampSeconds: number,
  rawBody: string,
): Promise<string> {
  const base = `${timestampSeconds}.${rawBody}`;
  const enc  = new TextEncoder();
  const key  = await crypto.subtle.importKey(
    "raw", enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false, ["sign"],
  );
  const sigBuf = await crypto.subtle.sign("HMAC", key, enc.encode(base));
  return bytesToHex(new Uint8Array(sigBuf));
}

// ── Cache helpers (Wave 5g / 5g-1) ───────────────────────────────────────────
// Versões canônicas das chaves de invalidação. Bumpar ao alterar persona/material.
const CACHE_PROMPT_VERSION         = "v1"; // bump ao alterar PERSONA_INSTRUCTIONS em chat-central
const CACHE_MATERIAL_SCOPE_VERSION = "v1"; // bump ao alterar MATERIAL_SCOPE em chat-central
const CACHE_MAX_ANSWER_CHARS       = 1200; // proxy ~200 output tokens quando usage indisponível (~6 chars/token)

// Pronomes pessoais em PT-BR: perguntas pessoais não são cacheadas (resultado varia por recruta).
const PERSONAL_PRONOUNS_RE =
  /\b(eu|meu|minha|meus|minhas|me|mim|você|voce|te|teu|tua|teus|tuas|nós|nos|nosso|nossa|nossos|nossas|lhe|lhes|seu|sua|seus|suas)\b/i;

// Saudações simples: não contêm conteúdo semântico útil para cachear.
const GREETINGS_RE =
  /^(oi|ol[aá]|hi|hello|hey|bom\s+dia|boa\s+tarde|boa\s+noite|tudo\s+bem|tudo\s+bom|e\s+a[ií]|beleza|boas|good\s+morning|good\s+afternoon|good\s+evening)[\s!?.]*$/i;

function normalizeQuestion(q: string): string {
  return q.toLowerCase().trim().replace(/\s+/g, " ").replace(/[^\w\s]/g, "");
}

/** Verifica se a PERGUNTA é elegível para cache (antes de chamar chat-central). */
function isCacheEligible(questionNorm: string): boolean {
  if (questionNorm.length === 0)   return false;
  if (questionNorm.length > 300)   return false;
  if (PERSONAL_PRONOUNS_RE.test(questionNorm)) return false;
  if (GREETINGS_RE.test(questionNorm))          return false;
  return true;
}

/** Verifica se a RESPOSTA é elegível para escrita no cache (após receber resposta). */
function isAnswerCacheEligible(
  answerText:   string,
  outputTokens: number | null,
  degraded:     boolean,
  truncated?:   boolean,
): boolean {
  if (degraded)                return false;
  if (truncated)               return false;
  if (!answerText.trim())      return false;
  if (outputTokens !== null && outputTokens > 200) return false;
  if (outputTokens === null   && answerText.length > CACHE_MAX_ANSWER_CHARS) return false;
  return true;
}

/** Razão legível para cache_skipped (telemetria). */
function cacheSkipReason(questionNorm: string): string {
  if (questionNorm.length === 0)                return "empty_question";
  if (questionNorm.length > 300)                return "question_too_long";
  if (GREETINGS_RE.test(questionNorm))          return "greeting";
  if (PERSONAL_PRONOUNS_RE.test(questionNorm))  return "personal_pronoun";
  return "not_eligible";
}

/** Razão legível para cache_write_skipped (telemetria). */
function answerSkipReason(
  answerText:   string,
  outputTokens: number | null,
  degraded:     boolean,
  truncated:    boolean,
): string {
  if (degraded)   return "degraded_response";
  if (truncated)  return "truncated_response";
  if (!answerText.trim()) return "empty_answer";
  if (outputTokens !== null && outputTokens > 200) return "output_tokens_exceeded";
  return "answer_too_long";
}

async function hashString(s: string): Promise<string> {
  const enc = new TextEncoder();
  const buf = await crypto.subtle.digest("SHA-256", enc.encode(s));
  return bytesToHex(new Uint8Array(buf));
}

function buildCacheKey(
  instrutor_slug: string,
  forca: string,
  access_mode: string,
  scope_type: string,
  model: string,
  questionHash: string,
): string {
  // 8 segmentos: slug:forca:access:scope:model:prompt_v:material_v:hash
  return `${instrutor_slug}:${forca}:${access_mode}:${scope_type}:${model}:${CACHE_PROMPT_VERSION}:${CACHE_MATERIAL_SCOPE_VERSION}:${questionHash}`;
}

async function lookupCache(
  supabaseService: ReturnType<typeof createClient>,
  cacheKey: string,
  request_id: string,
  started: number,
): Promise<{ answer_text: string; cache_id: string; hit_count: number; created_at: string } | null> {
  try {
    const { data, error } = await (supabaseService as any)
      .from("chat_response_cache")
      .select("answer_text, cache_id, hit_count, created_at")
      .eq("cache_key", cacheKey)
      .gt("expires_at", new Date().toISOString())
      .maybeSingle();
    if (error || !data) return null;
    const cacheAgeSec     = Math.floor((Date.now() - new Date(data.created_at as string).getTime()) / 1000);
    const answerTokensEst = Math.ceil((data.answer_text as string).length / 4);
    console.log("[INSTRUTOR_SEND_CACHE] cache_hit", {
      request_id,
      cache_id_prefix:      (data.cache_id as string).slice(0, 8),
      cache_hit_latency_ms: Date.now() - started,
      cache_age_seconds:    cacheAgeSec,
      cache_answer_tokens:  answerTokensEst,
    });
    return data as { answer_text: string; cache_id: string; hit_count: number; created_at: string };
  } catch {
    return null;
  }
}

async function writeCache(
  supabaseService: ReturnType<typeof createClient>,
  params: {
    cache_key:      string;
    question_hash:  string;
    question_norm:  string;
    answer_text:    string;
    instrutor_slug: string;
    forca:          string;
    access_mode:    string;
    scope_type:     string;
    output_tokens:  number | null;
    request_id:     string;
  },
): Promise<void> {
  try {
    await (supabaseService as any).from("chat_response_cache").upsert(
      {
        cache_key:      params.cache_key,
        question_hash:  params.question_hash,
        question_norm:  params.question_norm,
        answer_text:    params.answer_text,
        instrutor_slug: params.instrutor_slug,
        forca:          params.forca,
        access_mode:    params.access_mode,
        scope_type:     params.scope_type,
        model:                  "gpt-4o",
        prompt_version:         CACHE_PROMPT_VERSION,
        material_scope_version: CACHE_MATERIAL_SCOPE_VERSION,
        output_tokens:          params.output_tokens,
        expires_at:     new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
      },
      { onConflict: "cache_key" },
    );
    console.log("[INSTRUTOR_SEND_CACHE] cache_write", { request_id: params.request_id });
  } catch (err) {
    console.error("[INSTRUTOR_SEND_CACHE] cache_write_failed", {
      request_id: params.request_id, err: String(err),
    });
  }
}

async function incrementCacheHit(
  supabaseService: ReturnType<typeof createClient>,
  cache_id: string,
  hit_count: number,
): Promise<void> {
  try {
    await (supabaseService as any).from("chat_response_cache")
      .update({ hit_count: hit_count + 1, last_hit_at: new Date().toISOString() })
      .eq("cache_id", cache_id);
  } catch {
    // silent — hit count é informativo, não crítico
  }
}

// ── Handler principal ─────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  const request_id = crypto.randomUUID();
  const started    = Date.now();

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return json(405, { ok: false, reason: "method_not_allowed", request_id });
  }

  try {
    console.log("[INSTRUTOR_SEND_W1] start", {
      request_id,
      method:   req.method,
      has_auth: req.headers.has("authorization"),
      ms:       0,
    });

    const isSSE = req.headers.get("accept")?.includes("text/event-stream") ?? false;

    // ── 1. Authorization header ────────────────────────────────────────────────
    const authHeader = req.headers.get("Authorization") ?? "";
    console.log("[INSTRUTOR_SEND_AUTH]", { request_id, hasAuthHeader: !!authHeader });

    if (!authHeader.startsWith("Bearer ")) {
      return json(401, { ok: false, reason: "auth_required", request_id });
    }

    // ── 2. Parse do payload ───────────────────────────────────────────────────
    let body: {
      text?:               string;
      client_message_id?:  string;
      session_id?:         string;
      source?:             string;
      instrutor_slug?:     string;
      correlation_id?:     string;
    };

    try {
      body = await req.json();
    } catch {
      return json(400, { ok: false, reason: "invalid_json", request_id });
    }

    const { text, client_message_id, session_id, source, instrutor_slug } = body;

    if (!text?.trim() || !session_id || source !== "app") {
      return json(400, { ok: false, reason: "invalid_payload", request_id });
    }

    const clientMessageId = client_message_id ?? crypto.randomUUID();

    // ── 3. Resolver identidade via service_role + recrutas direto ─────────────
    const supabaseUrl  = Deno.env.get("SUPABASE_URL")!;
    const serviceKey   = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const authUid      = extractJwtSub(authHeader);

    if (!authUid) {
      console.warn("[INSTRUTOR_SEND_W1] jwt_sub_missing", { request_id, ms: Date.now() - started });
      return json(401, { ok: false, reason: "jwt_invalid", request_id });
    }

    const supabaseService = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const anonKey     = Deno.env.get("SUPABASE_ANON_KEY")!;
    const supabaseUser = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth:   { autoRefreshToken: false, persistSession: false },
    });

    const t_identity = Date.now();
    const { data: recruta, error: identidadeError } = await supabaseService
      .from("recrutas")
      .select("id, forca, plano, status, onboarding_concluido, instructor_profile_id, thread_id, nome_guerra, nome")
      .eq("auth_id", authUid)
      .maybeSingle();

    console.log("[INSTRUTOR_SEND_W1] step_identity_query", {
      request_id, identity_source: "service_direct",
      ms_identity: Date.now() - t_identity, ms: Date.now() - started,
    });

    if (identidadeError) {
      console.error("[INSTRUTOR_SEND_IDENTITY_ERROR]", {
        request_id, error: identidadeError.message,
        code: (identidadeError as any).code ?? null, ms: Date.now() - started,
      });
      return json(500, { ok: false, reason: "identity_error", request_id });
    }

    if (!recruta) {
      console.warn("[INSTRUTOR_SEND_IDENTITY]", {
        request_id, hasIdentity: false, ms: Date.now() - started,
      });
      return json(403, { ok: false, reason: "identity_not_found", request_id });
    }

    const ativo       = recruta.status?.toLowerCase() === "ativo";
    const tipo_acesso = recruta.plano;
    const identidade  = { ...recruta, ativo, tipo_acesso };

    console.log("[INSTRUTOR_SEND_IDENTITY]", {
      request_id,
      hasIdentity: true,
      recruta_id:  String(identidade.id ?? "").slice(0, 8),
      forca:       identidade.forca ?? null,
      onboarding_concluido: identidade.onboarding_concluido ?? false,
      has_instructor: !!identidade.instructor_profile_id,
      ativo,
      ms: Date.now() - started,
    });

    // ── 4. Validar identidade ─────────────────────────────────────────────────
    let validationReason: string | null = null;
    if (!identidade.id)                          validationReason = "recruta_missing";
    else if (!identidade.forca)                  validationReason = "forca_missing";
    else if (!identidade.onboarding_concluido)   validationReason = "onboarding_incomplete";
    else if (!identidade.instructor_profile_id)  validationReason = "instructor_missing";
    else if (!ativo)                             validationReason = "inactive_user";

    if (validationReason) {
      console.warn("[INSTRUTOR_SEND_W1] identity_validation_failed", {
        request_id, reason: validationReason, ms: Date.now() - started,
      });
      return json(403, { ok: false, reason: validationReason, request_id });
    }

    const recruta_id: string = identidade.id;
    const forca:      string = identidade.forca;
    const access_mode = tipo_acesso === "completo" ? "full_access" : "restricted";
    const resolvedSlug: string =
      instrutor_slug ?? identidade.instructor_profile_id ?? "objetivo";
    const correlationId =
      body.correlation_id ?? `chat:${recruta_id}:${clientMessageId}`;

    console.log("[INSTRUTOR_SEND_W1] identity_loaded", {
      request_id,
      recruta_id_prefix: recruta_id.slice(0, 8),
      forca, access_mode, instrutor_slug: resolvedSlug,
      is_sse: isSSE, ms: Date.now() - started,
    });

    // ── 5. Cache lookup (Wave 5g / 5g-1) ─────────────────────────────────────
    const questionNorm  = normalizeQuestion(text.trim());
    const questionHash  = await hashString(questionNorm);
    const scopeType     = access_mode === "restricted" ? "degustacao" : "full";
    const cacheKey      = buildCacheKey(resolvedSlug, forca, access_mode, scopeType, "gpt-4o", questionHash);
    const cacheEligible = isCacheEligible(questionNorm);

    let cacheEntry: { answer_text: string; cache_id: string; hit_count: number; created_at: string } | null = null;

    if (cacheEligible) {
      console.log("[INSTRUTOR_SEND_CACHE] cache_lookup", {
        request_id, instrutor_slug: resolvedSlug, forca,
        cache_key_prefix:     cacheKey.slice(0, 30),
        cache_write_eligible: true,
      });
      cacheEntry = await lookupCache(supabaseService, cacheKey, request_id, started);
    } else {
      console.log("[INSTRUTOR_SEND_CACHE] cache_skipped", {
        request_id,
        reason:               cacheSkipReason(questionNorm),
        question_len:         questionNorm.length,
        cache_write_eligible: false,
      });
    }

    // ── 6. Assinar e chamar Chat Central ──────────────────────────────────────
    const hmacSecret = Deno.env.get("QD_HMAC_SECRET");
    if (!hmacSecret) {
      console.error("[INSTRUTOR_SEND_W1] missing_hmac_secret", { request_id });
      return json(500, { ok: false, reason: "missing_hmac_secret", request_id });
    }

    const metadata = {
      source:                "instrutor-send",
      edge_function:         "instrutor-send",
      instructor_profile_id: identidade.instructor_profile_id,
      force:                 forca,
      thread_id:             identidade.thread_id ?? null,
    };

    const edgeRuntime = (globalThis as any).EdgeRuntime;

    // ── SSE path (Wave 5f) ────────────────────────────────────────────────────
    if (isSSE) {
      const encoder = new TextEncoder();

      // Cache hit em modo SSE: persistir resposta cacheada, emitir done
      if (cacheEntry) {
        const cachedReply   = cacheEntry.answer_text;
        const cacheId       = cacheEntry.cache_id;
        const hitCount      = cacheEntry.hit_count;

        const clientStream = new ReadableStream({
          async start(ctrl) {
            try {
              const t_rpc = Date.now();
              const { data: rpcData, error: rpcErr } = await supabaseUser.rpc(
                "rpc_chat_send_message",
                {
                  p_instrutor_slug:    resolvedSlug,
                  p_client_message_id: clientMessageId,
                  p_user_text:         text.trim(),
                  p_assistant_text:    cachedReply,
                  p_correlation_id:    correlationId,
                  p_metadata:          { ...metadata, from_cache: true },
                },
              );

              console.log("[INSTRUTOR_SEND_W1] rpc_send_success_cache_hit", {
                request_id, ms_rpc: Date.now() - t_rpc, ms: Date.now() - started,
              });

              if (rpcErr) {
                ctrl.enqueue(encoder.encode(
                  `data: ${JSON.stringify({
                    type:           "done",
                    ok:             false,
                    reason:         "persist_failed",
                    assistant_text: cachedReply,
                    correlation_id: correlationId,
                    from_cache:     true,
                  })}\n\n`
                ));
              } else {
                const conversa_id = (rpcData as any)?.conversa_id as string | undefined;
                ctrl.enqueue(encoder.encode(
                  `data: ${JSON.stringify({
                    type:           "done",
                    ok:             true,
                    conversa_id,
                    correlation_id: correlationId,
                    from_cache:     true,
                  })}\n\n`
                ));

                // Background: incrementar hit count + push notification
                const bgWork = Promise.all([
                  incrementCacheHit(supabaseService, cacheId, hitCount),
                  conversa_id ? (() => {
                    const chatNotifyUrl = `${supabaseUrl}/functions/v1/chat-notify`;
                    return fetch(chatNotifyUrl, {
                      method: "POST",
                      headers: {
                        "Content-Type": "application/json",
                        Authorization:  `Bearer ${serviceKey}`,
                        "x-qd-notify-key": serviceKey,
                      },
                      body: JSON.stringify({ recruta_id, conversa_id }),
                    }).catch(() => { /* silent */ });
                  })() : Promise.resolve(),
                ]);
                if (edgeRuntime?.waitUntil) {
                  edgeRuntime.waitUntil(bgWork);
                }
              }
            } catch (err) {
              console.error("[INSTRUTOR_SEND_W1] sse_cache_hit_error", {
                request_id, err: String(err), ms: Date.now() - started,
              });
              ctrl.enqueue(encoder.encode(sseErrorEvent("internal_error")));
            } finally {
              ctrl.close();
            }
          },
        });

        return new Response(clientStream, {
          status:  200,
          headers: { ...CORS_HEADERS, "content-type": "text/event-stream", "cache-control": "no-cache" },
        });
      }

      // Cache miss em modo SSE: chamar chat-central com stream:true, proxiar deltas
      console.log("[INSTRUTOR_SEND_CACHE] cache_miss", {
        request_id, instrutor_slug: resolvedSlug, forca,
        cache_write_eligible: cacheEligible,
      });

      const rawBodyStream = JSON.stringify({
        recruta_id,
        instrutor_slug: resolvedSlug,
        forca,
        access_mode,
        user_text:  text.trim(),
        session_id,
        stream:     true,
      });
      const ts_stream    = Math.floor(Date.now() / 1000);
      const sig_stream   = await signHmacSha256(hmacSecret, ts_stream, rawBodyStream);
      const chatCentralUrl = `${supabaseUrl}/functions/v1/chat-central`;

      console.log("[INSTRUTOR_SEND_W1] chat_central_request", {
        request_id, url: chatCentralUrl, ts: ts_stream,
        rawBodyLen: rawBodyStream.length, stream_mode: true, ms: Date.now() - started,
      });

      const t_central = Date.now();
      let centralRes: Response;
      try {
        centralRes = await fetch(chatCentralUrl, {
          method:  "POST",
          headers: {
            "content-type":    "application/json",
            authorization:     `Bearer ${serviceKey}`,
            "x-qd-timestamp":  String(ts_stream),
            "x-qd-signature":  `sha256=${sig_stream}`,
            accept:            "text/event-stream",
          },
          body: rawBodyStream,
        });
      } catch (fetchErr) {
        console.error("[INSTRUTOR_SEND_W1] chat_central_fetch_error", {
          request_id, err: String(fetchErr), ms: Date.now() - started,
        });
        const errStream = new ReadableStream({
          start(ctrl) {
            ctrl.enqueue(encoder.encode(sseErrorEvent("chat_central_unreachable")));
            ctrl.close();
          },
        });
        return new Response(errStream, {
          status:  200,
          headers: { ...CORS_HEADERS, "content-type": "text/event-stream", "cache-control": "no-cache" },
        });
      }

      if (!centralRes.ok || !centralRes.body) {
        console.error("[INSTRUTOR_SEND_W1] chat_central_bad_status", {
          request_id, http_status: centralRes.status, ms: Date.now() - started,
        });
        const errStream = new ReadableStream({
          start(ctrl) {
            ctrl.enqueue(encoder.encode(sseErrorEvent("chat_central_failed")));
            ctrl.close();
          },
        });
        return new Response(errStream, {
          status:  200,
          headers: { ...CORS_HEADERS, "content-type": "text/event-stream", "cache-control": "no-cache" },
        });
      }

      const centralReader  = centralRes.body.getReader();
      const centralDecoder = new TextDecoder();
      let   centralBuffer  = "";
      let   fullReplyText  = "";
      let   finalUsage: any = null;

      const clientStream = new ReadableStream({
        async start(ctrl) {
          try {
            outer: while (true) {
              const { done, value } = await centralReader.read();
              if (done) break;

              centralBuffer += centralDecoder.decode(value, { stream: true });
              const events = centralBuffer.split("\n\n");
              centralBuffer = events.pop() ?? "";

              for (const rawEvent of events) {
                if (!rawEvent.trim()) continue;
                let dataLine = "";
                for (const line of rawEvent.split("\n")) {
                  if (line.startsWith("data: ")) dataLine = line.slice(6).trim();
                }
                if (!dataLine) continue;

                try {
                  const ev = JSON.parse(dataLine) as any;

                  if (ev.type === "delta") {
                    fullReplyText += ev.delta;
                    // Proxy delta event to client immediately
                    ctrl.enqueue(encoder.encode(
                      `data: ${JSON.stringify({ type: "delta", delta: ev.delta })}\n\n`
                    ));

                  } else if (ev.type === "done") {
                    finalUsage = ev.usage ?? null;
                    const replyText = fullReplyText || (ev.text as string) || "";

                    console.log("[INSTRUTOR_SEND_W1] chat_central_stream_done", {
                      request_id,
                      ms_central: Date.now() - t_central,
                      replyLen:   replyText.length,
                      ms:         Date.now() - started,
                    });

                    // RPC persist (síncrono antes de emitir done ao cliente —
                    // garante que fetchMensagens() do cliente encontrará a mensagem no DB)
                    const t_rpc = Date.now();
                    console.log("[INSTRUTOR_SEND_W1] rpc_send_start", {
                      request_id, instrutor_slug: resolvedSlug, ms: Date.now() - started,
                    });

                    const { data: rpcData, error: rpcErr } = await supabaseUser.rpc(
                      "rpc_chat_send_message",
                      {
                        p_instrutor_slug:    resolvedSlug,
                        p_client_message_id: clientMessageId,
                        p_user_text:         text.trim(),
                        p_assistant_text:    replyText,
                        p_correlation_id:    ev.correlation_id ?? correlationId,
                        p_metadata:          metadata,
                      },
                    );

                    const ms_rpc       = Date.now() - t_rpc;
                    const finalCorrId  = ev.correlation_id ?? correlationId;
                    const conversa_id  = (rpcData as any)?.conversa_id as string | undefined;

                    if (rpcErr) {
                      console.error("[INSTRUTOR_SEND_W1] rpc_send_error", {
                        request_id, error: rpcErr.message,
                        code: (rpcErr as any).code ?? null, ms_rpc, ms: Date.now() - started,
                      });
                      ctrl.enqueue(encoder.encode(
                        `data: ${JSON.stringify({
                          type:           "done",
                          ok:             false,
                          reason:         "persist_failed",
                          assistant_text: replyText,
                          correlation_id: finalCorrId,
                        })}\n\n`
                      ));
                    } else {
                      console.log("[INSTRUTOR_SEND_W1] rpc_send_success", {
                        request_id, correlation_id: finalCorrId,
                        ms_rpc, ms: Date.now() - started,
                      });
                      ctrl.enqueue(encoder.encode(
                        `data: ${JSON.stringify({
                          type:           "done",
                          ok:             true,
                          conversa_id,
                          correlation_id: finalCorrId,
                        })}\n\n`
                      ));

                      // Background: cache write + push notification
                      const outputTokens = finalUsage?.output_tokens ?? null;
                      const isDegraded   = ev.degraded  === true;
                      const isTruncated  = ev.truncated === true;
                      const shouldCache  = cacheEligible &&
                        isAnswerCacheEligible(replyText, outputTokens, isDegraded, isTruncated);

                      if (!shouldCache && cacheEligible) {
                        console.log("[INSTRUTOR_SEND_CACHE] cache_write_skipped", {
                          request_id,
                          reason:        answerSkipReason(replyText, outputTokens, isDegraded, isTruncated),
                          output_tokens: outputTokens,
                          answer_len:    replyText.length,
                        });
                      }

                      const bgWork = Promise.all([
                        shouldCache ? writeCache(supabaseService, {
                          cache_key:      cacheKey,
                          question_hash:  questionHash,
                          question_norm:  questionNorm,
                          answer_text:    replyText,
                          instrutor_slug: resolvedSlug,
                          forca,
                          access_mode,
                          scope_type:     scopeType,
                          output_tokens:  outputTokens,
                          request_id,
                        }) : Promise.resolve(),

                        conversa_id ? (() => {
                          const chatNotifyUrl = `${supabaseUrl}/functions/v1/chat-notify`;
                          return fetch(chatNotifyUrl, {
                            method:  "POST",
                            headers: {
                              "Content-Type":    "application/json",
                              Authorization:     `Bearer ${serviceKey}`,
                              "x-qd-notify-key": serviceKey,
                            },
                            body: JSON.stringify({ recruta_id, conversa_id }),
                          }).catch(() => { /* silent */ });
                        })() : Promise.resolve(),
                      ]);

                      if (edgeRuntime?.waitUntil) {
                        edgeRuntime.waitUntil(bgWork);
                      }
                    }

                    break outer;

                  } else if (ev.type === "error") {
                    console.error("[INSTRUTOR_SEND_W1] chat_central_error_event", {
                      request_id, reason: ev.reason, ms: Date.now() - started,
                    });
                    ctrl.enqueue(encoder.encode(
                      `data: ${JSON.stringify({ type: "error", reason: ev.reason ?? "chat_central_error" })}\n\n`
                    ));
                    break outer;
                  }
                } catch {
                  // skip malformed event
                }
              }
            }
          } catch (err) {
            console.error("[INSTRUTOR_SEND_W1] sse_proxy_error", {
              request_id, err: String(err), ms: Date.now() - started,
            });
            ctrl.enqueue(encoder.encode(sseErrorEvent("proxy_error")));
          } finally {
            ctrl.close();
          }
        },
      });

      return new Response(clientStream, {
        status:  200,
        headers: {
          ...CORS_HEADERS,
          "content-type":  "text/event-stream",
          "cache-control": "no-cache",
        },
      });
    }

    // ── JSON path (não-SSE — backward compat) ─────────────────────────────────

    // Cache hit em modo JSON: retornar resposta cacheada diretamente
    if (cacheEntry) {
      const cachedReply = cacheEntry.answer_text;
      const cacheId     = cacheEntry.cache_id;
      const hitCount    = cacheEntry.hit_count;

      const t_rpc = Date.now();
      const { data: rpcData, error: rpcErr } = await supabaseUser.rpc(
        "rpc_chat_send_message",
        {
          p_instrutor_slug:    resolvedSlug,
          p_client_message_id: clientMessageId,
          p_user_text:         text.trim(),
          p_assistant_text:    cachedReply,
          p_correlation_id:    correlationId,
          p_metadata:          { ...metadata, from_cache: true },
        },
      );

      console.log("[INSTRUTOR_SEND_W1] rpc_send_cache_hit", {
        request_id, ms_rpc: Date.now() - t_rpc, ms: Date.now() - started,
      });

      if (rpcErr) {
        return json(207, {
          ok:             false,
          reason:         "persist_failed",
          assistant_text: cachedReply,
          correlation_id: correlationId,
          from_cache:     true,
          request_id,
          ms:             Date.now() - started,
        });
      }

      // Background: hit count
      const bgHit = incrementCacheHit(supabaseService, cacheId, hitCount);
      if (edgeRuntime?.waitUntil) {
        edgeRuntime.waitUntil(bgHit);
      } else {
        await bgHit;
      }

      return json(200, {
        ok: true,
        ...(rpcData != null && typeof rpcData === "object" ? (rpcData as object) : {}),
        assistant_text:  cachedReply,
        correlation_id:  correlationId,
        from_cache:      true,
        request_id,
        ms: Date.now() - started,
      });
    }

    // Cache miss em modo JSON: chamar chat-central normalmente
    console.log("[INSTRUTOR_SEND_CACHE] cache_miss", {
      request_id, instrutor_slug: resolvedSlug, forca,
      cache_write_eligible: cacheEligible,
    });

    const rawBody = JSON.stringify({
      recruta_id,
      instrutor_slug: resolvedSlug,
      forca,
      access_mode,
      user_text:  text.trim(),
      session_id,
    });

    const ts        = Math.floor(Date.now() / 1000);
    const signature = await signHmacSha256(hmacSecret, ts, rawBody);
    const chatCentralUrl = `${supabaseUrl}/functions/v1/chat-central`;

    console.log("[INSTRUTOR_SEND_W1] chat_central_request", {
      request_id, url: chatCentralUrl, ts, rawBodyLen: rawBody.length,
      sigPrefix: signature.slice(0, 12), ms: Date.now() - started,
    });

    const t_central = Date.now();
    const centralRes = await fetch(chatCentralUrl, {
      method:  "POST",
      headers: {
        "content-type":   "application/json",
        authorization:    `Bearer ${serviceKey}`,
        "x-qd-timestamp": String(ts),
        "x-qd-signature": `sha256=${signature}`,
      },
      body: rawBody,
    });

    let centralData: {
      ok:            boolean;
      reply?:        string;
      correlation_id?: string;
      reason?:       string;
      request_id?:   string;
    } = { ok: false };

    try {
      centralData = await centralRes.json();
    } catch {
      console.error("[INSTRUTOR_SEND_W1] chat_central_response_status", {
        request_id, http_status: centralRes.status, parse_error: true, ms: Date.now() - started,
      });
      return json(502, { ok: false, reason: "chat_central_bad_response", request_id });
    }

    console.log("[INSTRUTOR_SEND_W1] chat_central_response_status", {
      request_id,
      http_status:        centralRes.status,
      central_ok:         centralData.ok,
      central_reason:     centralData.reason ?? null,
      central_request_id: centralData.request_id ?? null,
      has_reply:          !!centralData.reply,
      ms_central:         Date.now() - t_central,
      ms:                 Date.now() - started,
    });

    if (!centralRes.ok || !centralData.ok || !centralData.reply) {
      console.error("[INSTRUTOR_SEND_W1] chat_central_error", {
        request_id, http_status: centralRes.status,
        reason: centralData.reason ?? "no_reply",
        central_request_id: centralData.request_id ?? null,
        ms: Date.now() - started,
      });
      return json(502, {
        ok:     false,
        reason: "chat_central_failed",
        detail: centralData.reason ?? "no_reply",
        request_id,
      });
    }

    const assistantReply     = centralData.reply;
    const isDegradedJson     = (centralData as any).degraded === true;
    const finalCorrelationId = centralData.correlation_id ?? correlationId;

    // ── Persistir via rpc_chat_send_message ───────────────────────────────────
    const t_rpc_start = Date.now();
    console.log("[INSTRUTOR_SEND_W1] rpc_send_start", {
      request_id, correlation_id: finalCorrelationId,
      instrutor_slug: resolvedSlug, ms: Date.now() - started,
    });

    const { data: rpcData, error: rpcErr } = await supabaseUser.rpc(
      "rpc_chat_send_message",
      {
        p_instrutor_slug:    resolvedSlug,
        p_client_message_id: clientMessageId,
        p_user_text:         text.trim(),
        p_assistant_text:    assistantReply,
        p_correlation_id:    finalCorrelationId,
        p_metadata:          metadata,
      },
    );

    if (rpcErr) {
      console.error("[INSTRUTOR_SEND_W1] rpc_send_error", {
        request_id, correlation_id: finalCorrelationId,
        error: rpcErr.message, code: (rpcErr as any).code ?? null,
        ms: Date.now() - started,
      });
      return json(207, {
        ok:             false,
        reason:         "persist_failed",
        assistant_text: assistantReply,
        correlation_id: finalCorrelationId,
        request_id,
        ms:             Date.now() - started,
      });
    }

    console.log("[INSTRUTOR_SEND_W1] rpc_send_success", {
      request_id, correlation_id: finalCorrelationId,
      ms_rpc: Date.now() - t_rpc_start, ms: Date.now() - started,
    });

    const conversa_id = (rpcData as any)?.conversa_id as string | undefined;

    // Background: cache write + push notification
    // No path JSON, chat-central não retorna usage — usar length da resposta como proxy.
    const shouldCacheJson = cacheEligible &&
      isAnswerCacheEligible(assistantReply, null, isDegradedJson);

    if (!shouldCacheJson && cacheEligible) {
      console.log("[INSTRUTOR_SEND_CACHE] cache_write_skipped", {
        request_id,
        reason:     answerSkipReason(assistantReply, null, isDegradedJson, false),
        answer_len: assistantReply.length,
      });
    }

    const bgWork = Promise.all([
      shouldCacheJson ? writeCache(supabaseService, {
        cache_key:      cacheKey,
        question_hash:  questionHash,
        question_norm:  questionNorm,
        answer_text:    assistantReply,
        instrutor_slug: resolvedSlug,
        forca,
        access_mode,
        scope_type:     scopeType,
        output_tokens:  null,  // não disponível no path JSON (chat-central não retorna usage)
        request_id,
      }) : Promise.resolve(),

      conversa_id ? (() => {
        const chatNotifyUrl = `${supabaseUrl}/functions/v1/chat-notify`;
        console.log("[INSTRUTOR_SEND_W1] chat_notify_dispatched", {
          request_id,
          conversa_id_prefix: conversa_id.slice(0, 8),
          recruta_id_prefix:  recruta_id.slice(0, 8),
          ms: Date.now() - started,
        });
        return fetch(chatNotifyUrl, {
          method:  "POST",
          headers: {
            "Content-Type":    "application/json",
            Authorization:     `Bearer ${serviceKey}`,
            "x-qd-notify-key": serviceKey,
          },
          body: JSON.stringify({ recruta_id, conversa_id }),
        }).then(async (notifyRes) => {
          const bodyText = await notifyRes.text().catch(() => "");
          console.log("[INSTRUTOR_SEND_W1] chat_notify_status", {
            request_id,
            http_status:  notifyRes.status,
            ok:           notifyRes.ok,
            body_prefix:  bodyText.slice(0, 100),
          });
        }).catch((err) => {
          console.error("[INSTRUTOR_SEND_W1] chat_notify_error", {
            request_id, error_code: String(err).slice(0, 80),
          });
        });
      })() : Promise.resolve(),
    ]);

    if (edgeRuntime?.waitUntil) {
      edgeRuntime.waitUntil(bgWork);
    } else {
      await bgWork;
    }

    return json(200, {
      ok: true,
      ...(rpcData != null && typeof rpcData === "object" ? (rpcData as object) : {}),
      assistant_text:  assistantReply,
      correlation_id:  finalCorrelationId,
      request_id,
      ms: Date.now() - started,
    });

  } catch (err) {
    console.error("[INSTRUTOR_SEND_W1] exception", {
      request_id, err: String(err), ms: Date.now() - started,
    });
    return json(500, { ok: false, reason: "internal_error", request_id });
  }
});
