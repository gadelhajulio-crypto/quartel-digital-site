// RCC Wave 1 — Instrutor Send
// Orquestrador: autentica, delega ao Chat Central, persiste via RPC.
// Nunca escreve tabelas diretamente. Nunca emite C5. Nunca decide unread.

import { createClient } from "supabase";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
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

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Assina `${timestampSeconds}.${rawBody}` — exatamente o que chat-central verifica.
async function signHmacSha256(
  secret: string,
  timestampSeconds: number,
  rawBody: string,
): Promise<string> {
  const base = `${timestampSeconds}.${rawBody}`;
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sigBuf = await crypto.subtle.sign("HMAC", key, enc.encode(base));
  return bytesToHex(new Uint8Array(sigBuf));
}

// ── Handler principal ─────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  const request_id = crypto.randomUUID();
  const started = Date.now();

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return json(405, { ok: false, reason: "method_not_allowed", request_id });
  }

  try {
    console.log("[INSTRUTOR_SEND_W1] start", {
      request_id,
      method: req.method,
      has_auth: req.headers.has("authorization"),
      ms: 0,
    });

    // ── 1. Capturar Authorization header ──────────────────────────────────────
    // Repassado integralmente ao cliente Supabase para que auth.uid() seja
    // resolvido corretamente e as views RCC respondam ao role authenticated.
    const authHeader = req.headers.get("Authorization") ?? "";

    console.log("[INSTRUTOR_SEND_AUTH]", {
      request_id,
      hasAuthHeader: !!authHeader,
    });

    if (!authHeader.startsWith("Bearer ")) {
      return json(401, { ok: false, reason: "auth_required", request_id });
    }

    // ── 2. Parse do payload ───────────────────────────────────────────────────
    let body: {
      text?: string;
      client_message_id?: string;
      session_id?: string;
      source?: string;
      instrutor_slug?: string;
      correlation_id?: string;
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

    // TODO RCC: frontend deve gerar client_message_id para retry idempotente.
    const clientMessageId = client_message_id ?? crypto.randomUUID();

    // ── 3. Ler identidade via v_identidade_recruta com JWT authenticated ──────
    // NÃO usar service_role aqui — a view tem GRANT SELECT TO authenticated
    // e filtra por auth.uid(). O service_role não tem o grant e não seta uid().
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const supabaseUser = createClient(supabaseUrl, anonKey, {
      global: {
        headers: {
          Authorization: authHeader,
        },
      },
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const t_identity_start = Date.now();
    const { data: identidade, error: identidadeError } = await supabaseUser
      .from("v_identidade_recruta")
      .select("*")
      .maybeSingle();

    console.log("[INSTRUTOR_SEND_W1] step_identity_query", {
      request_id,
      ms_identity: Date.now() - t_identity_start,
      ms: Date.now() - started,
    });

    if (identidadeError) {
      console.error("[INSTRUTOR_SEND_IDENTITY_ERROR]", {
        request_id,
        error: identidadeError.message,
        code: (identidadeError as any).code ?? null,
        ms: Date.now() - started,
      });
      return json(500, { ok: false, reason: "identity_error", request_id });
    }

    if (!identidade) {
      console.warn("[INSTRUTOR_SEND_IDENTITY]", {
        request_id,
        hasIdentity: false,
        ms: Date.now() - started,
      });
      return json(403, { ok: false, reason: "identity_not_found", request_id });
    }

    console.log("[INSTRUTOR_SEND_IDENTITY]", {
      request_id,
      hasIdentity: true,
      recruta_id: String(identidade.id ?? "").slice(0, 8),
      forca: identidade.forca ?? null,
      onboarding_concluido: identidade.onboarding_concluido ?? false,
      has_instructor: !!identidade.instructor_profile_id,
      ativo: identidade.ativo ?? false,
      ms: Date.now() - started,
    });

    // ── 4. Validar campos obrigatórios da identidade ──────────────────────────
    let validationReason: string | null = null;

    if (!identidade.id) validationReason = "recruta_missing";
    else if (!identidade.forca) validationReason = "forca_missing";
    else if (!identidade.onboarding_concluido) validationReason = "onboarding_incomplete";
    else if (!identidade.instructor_profile_id) validationReason = "instructor_missing";
    else if (!identidade.ativo) validationReason = "inactive_user";

    if (validationReason) {
      console.warn("[INSTRUTOR_SEND_W1] identity_validation_failed", {
        request_id,
        reason: validationReason,
        ms: Date.now() - started,
      });
      return json(403, { ok: false, reason: validationReason, request_id });
    }

    const recruta_id: string = identidade.id;
    const forca: string = identidade.forca;
    const access_mode =
      identidade.tipo_acesso === "completo" ? "full_access" : "restricted";
    const resolvedSlug: string =
      instrutor_slug ?? identidade.instructor_profile_id ?? "objetivo";
    const idempotency_key = `chat:${recruta_id}:${clientMessageId}`;

    const correlationId =
      body.correlation_id ?? `chat:${recruta_id}:${clientMessageId}`;

    console.log("[INSTRUTOR_SEND_W1] identity_loaded", {
      request_id,
      recruta_id_prefix: recruta_id.slice(0, 8),
      forca,
      access_mode,
      instrutor_slug: resolvedSlug,
      ms: Date.now() - started,
    });

    // ── 5. Assinar e chamar Chat Central ──────────────────────────────────────
    const hmacSecret = Deno.env.get("QD_HMAC_SECRET");
    if (!hmacSecret) {
      console.error("[INSTRUTOR_SEND_W1] missing_hmac_secret", { request_id });
      return json(500, { ok: false, reason: "missing_hmac_secret", request_id });
    }

    // rawBody: string exato enviado no body — chat-central faz req.text() e
    // verifica HMAC de `${ts}.${rawBody}`. Assinamos exatamente o mesmo.
    const rawBody = JSON.stringify({
      recruta_id,
      instrutor_slug: resolvedSlug,
      forca,
      access_mode,
      user_text: text.trim(),
      session_id,
    });

    const ts = Math.floor(Date.now() / 1000);
    const signature = await signHmacSha256(hmacSecret, ts, rawBody);

    const chatCentralUrl = `${supabaseUrl}/functions/v1/chat-central`;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    console.log("[INSTRUTOR_SEND_W1] chat_central_request", {
      request_id,
      url: chatCentralUrl,
      ts,
      rawBodyLen: rawBody.length,
      sigPrefix: signature.slice(0, 12),
      ms: Date.now() - started,
    });

    const t_central_start = Date.now();
    const centralRes = await fetch(chatCentralUrl, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${serviceKey}`,
        "x-qd-timestamp": String(ts),
        "x-qd-signature": `sha256=${signature}`,
      },
      body: rawBody,
    });

    let centralData: {
      ok: boolean;
      reply?: string;
      correlation_id?: string;
      reason?: string;
      request_id?: string;
    } = { ok: false };

    try {
      centralData = await centralRes.json();
    } catch {
      console.error("[INSTRUTOR_SEND_W1] chat_central_response_status", {
        request_id,
        http_status: centralRes.status,
        parse_error: true,
        ms: Date.now() - started,
      });
      return json(502, {
        ok: false,
        reason: "chat_central_bad_response",
        request_id,
      });
    }

    console.log("[INSTRUTOR_SEND_W1] chat_central_response_status", {
      request_id,
      http_status: centralRes.status,
      central_ok: centralData.ok,
      central_reason: centralData.reason ?? null,
      central_request_id: centralData.request_id ?? null,
      has_reply: !!centralData.reply,
      ms_central: Date.now() - t_central_start,
      ms: Date.now() - started,
    });

    if (!centralRes.ok || !centralData.ok || !centralData.reply) {
      console.error("[INSTRUTOR_SEND_W1] chat_central_error", {
        request_id,
        http_status: centralRes.status,
        reason: centralData.reason ?? "no_reply",
        central_request_id: centralData.request_id ?? null,
        ms: Date.now() - started,
      });

      console.log("[INSTRUTOR_SEND_CHAT_CENTRAL]", {
        request_id,
        success: false,
        reason: centralData.reason ?? "no_reply",
        ms: Date.now() - started,
      });

      return json(502, {
        ok: false,
        reason: "chat_central_failed",
        detail: centralData.reason ?? "no_reply",
        request_id,
      });
    }

    const assistantReply = centralData.reply;
    const finalCorrelationId = centralData.correlation_id ?? correlationId;

    console.log("[INSTRUTOR_SEND_CHAT_CENTRAL]", {
      request_id,
      success: true,
      correlation_id: finalCorrelationId,
      replyLen: assistantReply.length,
      ms: Date.now() - started,
    });

    // ── 6. Persistir via rpc_chat_send_message com JWT autenticado ────────────
    // supabaseUser já tem o JWT — auth.uid() será resolvido corretamente.
    const metadata = {
      source: "instrutor-send",
      edge_function: "instrutor-send",
      instructor_profile_id: identidade.instructor_profile_id,
      force: forca,
      thread_id: identidade.thread_id ?? null,
    };

    const t_rpc_start = Date.now();
    console.log("[INSTRUTOR_SEND_W1] rpc_send_start", {
      request_id,
      correlation_id: finalCorrelationId,
      instrutor_slug: resolvedSlug,
      ms: Date.now() - started,
    });

    const { data: rpcData, error: rpcErr } = await supabaseUser.rpc(
      "rpc_chat_send_message",
      {
        p_instrutor_slug: resolvedSlug,
        p_client_message_id: clientMessageId,
        p_user_text: text.trim(),
        p_assistant_text: assistantReply,
        p_correlation_id: finalCorrelationId,
        p_metadata: metadata,
      },
    );

    if (rpcErr) {
      console.error("[INSTRUTOR_SEND_W1] rpc_send_error", {
        request_id,
        correlation_id: finalCorrelationId,
        error: rpcErr.message,
        code: (rpcErr as any).code ?? null,
        ms: Date.now() - started,
      });

      console.log("[INSTRUTOR_SEND_RPC_PERSIST]", {
        request_id,
        success: false,
        error: rpcErr.message,
        ms: Date.now() - started,
      });

      // 207: resposta do instrutor gerada mas persistência falhou
      return json(207, {
        ok: false,
        reason: "persist_failed",
        assistant_text: assistantReply,
        correlation_id: finalCorrelationId,
        request_id,
        ms: Date.now() - started,
      });
    }

    console.log("[INSTRUTOR_SEND_W1] rpc_send_success", {
      request_id,
      correlation_id: finalCorrelationId,
      has_rpc_data: !!rpcData,
      ms_rpc: Date.now() - t_rpc_start,
      ms: Date.now() - started,
    });

    console.log("[INSTRUTOR_SEND_RPC_PERSIST]", {
      request_id,
      success: true,
      correlation_id: finalCorrelationId,
      ms: Date.now() - started,
    });

    // ── 9. Notificação push — fora do caminho crítico via EdgeRuntime.waitUntil ──
    //
    // Wave 5c: chat-notify é movido para APÓS o return usando EdgeRuntime.waitUntil().
    // Antes: await fetch(chat-notify) bloqueava ~300–600ms antes do return.
    // Agora: EdgeRuntime.waitUntil(promise) mantém o isolate vivo após o return,
    //        garantindo entrega do push sem custo percebido pelo usuário.
    //
    // Fallback: se EdgeRuntime não estiver disponível (ambiente não-Supabase),
    // a promise é awaited diretamente para garantir entrega.
    const conversa_id = (rpcData as any)?.conversa_id as string | undefined;

    if (!conversa_id) {
      console.warn("[INSTRUTOR_SEND_W1] chat_notify_skipped", {
        request_id,
        reason: "no_conversa_id",
        has_rpc_data: !!rpcData,
        rpc_data_keys: rpcData != null && typeof rpcData === "object"
          ? Object.keys(rpcData as object)
          : null,
        ms: Date.now() - started,
      });
    } else {
      const chatNotifyUrl = `${supabaseUrl}/functions/v1/chat-notify`;
      const notifyServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

      console.log("[INSTRUTOR_SEND_W1] chat_notify_dispatched", {
        request_id,
        conversa_id_prefix: conversa_id.slice(0, 8),
        recruta_id_prefix: recruta_id.slice(0, 8),
        notify_key_prefix: notifyServiceKey.slice(0, 6) || "(empty)",
        notify_key_missing: notifyServiceKey === "",
        ms: Date.now() - started,
      });

      const t_notify_start = Date.now();
      const notifyPromise = fetch(chatNotifyUrl, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${notifyServiceKey}`,
          "x-qd-notify-key": notifyServiceKey,
        },
        body: JSON.stringify({ recruta_id, conversa_id }),
      }).then(async (notifyRes) => {
        let notifyBodyRaw = "";
        try { notifyBodyRaw = await notifyRes.text(); } catch { /* ignorado */ }
        console.log("[INSTRUTOR_SEND_W1] chat_notify_status", {
          request_id,
          http_status: notifyRes.status,
          ok: notifyRes.ok,
          body_prefix: notifyBodyRaw.slice(0, 100),
          ms_notify: Date.now() - t_notify_start,
          ms: Date.now() - started,
        });
      }).catch((err) => {
        console.error("[INSTRUTOR_SEND_W1] chat_notify_error", {
          request_id,
          error_code: String(err).slice(0, 80),
          ms_notify: Date.now() - t_notify_start,
          ms: Date.now() - started,
        });
      });

      // EdgeRuntime.waitUntil: mantém o isolate vivo após o return para entregar o push.
      // Disponível no Supabase Edge Runtime >= 1.19.0.
      // Fallback para await se não disponível (ex: teste local).
      // deno-lint-ignore no-explicit-any
      const edgeRuntime = (globalThis as any).EdgeRuntime;
      if (edgeRuntime?.waitUntil) {
        edgeRuntime.waitUntil(notifyPromise);
      } else {
        await notifyPromise;
      }
    }

    return json(200, {
      ok: true,
      ...(rpcData != null && typeof rpcData === "object" ? (rpcData as object) : {}),
      assistant_text: assistantReply,
      correlation_id: finalCorrelationId,
      request_id,
      ms: Date.now() - started,
    });
  } catch (err) {
    console.error("[INSTRUTOR_SEND_W1] exception", {
      request_id,
      err: String(err),
      ms: Date.now() - started,
    });
    return json(500, { ok: false, reason: "internal_error", request_id });
  }
});
