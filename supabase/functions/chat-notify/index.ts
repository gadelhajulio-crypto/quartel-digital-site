// Wave 5a-4 — Chat Notify
// Entrega push para o recruta quando o instrutor envia uma mensagem.
//
// INVARIANTES:
//   - chamado apenas por instrutor-send (function-to-function, service_role)
//   - nunca exposto ao frontend
//   - fire-and-forget: nunca bloqueia a resposta de instrutor-send
//   - token inválido (DeviceNotRegistered/InvalidCredentials) → is_active=false silencioso
//   - nunca loga token completo
//   - plataforma restrita a 'ios' | 'android' (contrato da tabela)

import { createClient } from "supabase";

const EXPO_PUSH_URL = "https://exp.host/--/api/v2/push/send";

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json(405, { ok: false, reason: "method_not_allowed" });
  }

  // ── 1. Autenticação interna: apenas instrutor-send via service_role ──────────
  // Mecanismo duplo:
  //   (a) x-qd-notify-key  — header customizado, não tocado pelo gateway Supabase
  //   (b) Authorization    — fallback legado; pode ser reescrito pelo gateway
  // A comparação usa (a) como primário; (b) como fallback para compatibilidade.
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const internalKey = req.headers.get("x-qd-notify-key") ?? "";
  const authHeader  = req.headers.get("Authorization") ?? "";

  const authorizedViaCustomHeader = internalKey !== "" && internalKey === serviceKey;
  const authorizedViaBearer       = authHeader === `Bearer ${serviceKey}`;

  if (!authorizedViaCustomHeader && !authorizedViaBearer) {
    // Log diagnóstico: nunca expõe a chave completa — apenas prefixos de 6 chars
    console.warn("[CHAT_NOTIFY] unauthorized", {
      has_auth_header: authHeader !== "",
      has_custom_header: internalKey !== "",
      bearer_prefix: authHeader.startsWith("Bearer ") ? authHeader.slice(7, 13) : "(no_bearer)",
      custom_prefix: internalKey.slice(0, 6) || "(empty)",
      expected_prefix: serviceKey.slice(0, 6) || "(empty_key)",
      key_missing: serviceKey === "",
    });
    return json(401, { ok: false, reason: "unauthorized" });
  }

  // ── 2. Parse payload ────────────────────────────────────────────────────────
  let body: { recruta_id?: string; conversa_id?: string };
  try {
    body = await req.json();
  } catch {
    return json(400, { ok: false, reason: "invalid_json" });
  }

  const { recruta_id, conversa_id } = body;

  if (!recruta_id || !conversa_id) {
    return json(400, { ok: false, reason: "missing_fields" });
  }

  console.log("[CHAT_C5] push_dispatch_started", {
    recruta_id_prefix: recruta_id.slice(0, 8),
    conversa_id_prefix: conversa_id.slice(0, 8),
  });

  // ── 3. Buscar tokens ativos via service_role ────────────────────────────────
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;

  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: tokens, error: tokensError } = await supabase
    .from("recruta_push_tokens")
    .select("id, token, platform")
    .eq("recruta_id", recruta_id)
    .eq("is_active", true);

  if (tokensError) {
    console.error("[CHAT_C5] push_dispatch_failed", {
      error_code: tokensError.code ?? "db_error",
      status: tokensError.message?.slice(0, 40),
    });
    return json(500, { ok: false, reason: "db_error" });
  }

  console.log("[CHAT_C5] push_tokens_found", {
    count: tokens?.length ?? 0,
    recruta_id_prefix: recruta_id.slice(0, 8),
  });

  if (!tokens || tokens.length === 0) {
    console.log("[CHAT_C5] push_dispatch_succeeded", { sent: 0, reason: "no_tokens" });
    return json(200, { ok: true, sent: 0 });
  }

  // ── 4. Enviar batch ao Expo Push API ───────────────────────────────────────
  const messages = tokens.map((t) => ({
    to: t.token,
    sound: "default",
    title: "Instrutor respondeu",
    body: "Há uma nova atualização operacional.",
    data: { conversa_id, type: "chat_reply" },
  }));

  let pushResponse: Response;
  try {
    pushResponse = await fetch(EXPO_PUSH_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(messages),
    });
  } catch (err) {
    console.error("[CHAT_C5] push_dispatch_failed", {
      error_code: "fetch_error",
      status: String(err).slice(0, 40),
    });
    return json(502, { ok: false, reason: "push_api_unreachable" });
  }

  if (!pushResponse.ok) {
    console.error("[CHAT_C5] push_dispatch_failed", {
      error_code: "push_api_error",
      status: String(pushResponse.status),
    });
    return json(502, { ok: false, reason: "push_api_error" });
  }

  // ── 5. Processar receipts — invalidar tokens com erro permanente ───────────
  let responseBody: { data?: Array<{ status: string; details?: { error?: string } }> };
  try {
    responseBody = await pushResponse.json();
  } catch {
    // Se não conseguir parsear receipts, considera enviado mesmo assim
    console.log("[CHAT_C5] push_dispatch_succeeded", {
      sent: messages.length,
      receipts_parsed: false,
    });
    return json(200, { ok: true, sent: messages.length });
  }

  const receipts = responseBody?.data ?? [];
  const invalidTokenIds: string[] = [];
  const PERMANENT_ERRORS = new Set(["DeviceNotRegistered", "InvalidCredentials"]);

  receipts.forEach((receipt, i) => {
    if (receipt.status === "error") {
      const errCode = receipt.details?.error ?? "unknown";
      if (PERMANENT_ERRORS.has(errCode) && tokens[i]) {
        invalidTokenIds.push(tokens[i].id);
        console.log("[CHAT_C5] push_token_invalidated", {
          error_code: errCode,
          platform: tokens[i].platform,
        });
      }
    }
  });

  // Invalidar tokens mortos — fire-and-forget (não bloqueia resposta)
  if (invalidTokenIds.length > 0) {
    supabase
      .from("recruta_push_tokens")
      .update({ is_active: false })
      .in("id", invalidTokenIds)
      .then(({ error }) => {
        if (error) {
          console.error("[CHAT_C5] push_dispatch_failed", {
            error_code: "invalidation_error",
            status: error.message?.slice(0, 40),
          });
        }
      });
  }

  const sent = receipts.filter((r) => r.status === "ok").length;
  console.log("[CHAT_C5] push_dispatch_succeeded", {
    sent,
    total: messages.length,
    invalidated: invalidTokenIds.length,
  });

  return json(200, { ok: true, sent, total: messages.length });
});
