import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  stagePublicationEnvelopeV1,
  stageReleaseManifestV1,
} from "../_shared/qd-curriculum-publication-v1/receiver-core.ts";
import { SupabaseShadowStagingStore } from "../_shared/qd-curriculum-publication-v1/supabase-staging-store.ts";
import { parseTransportKeyringJson } from "../_shared/qd-curriculum-publication-v1/transport-auth.ts";
import { handleShadowReceiver } from "./handler.ts";

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "no-store",
    },
  });
}

Deno.serve(async (request) => {
  const enabled = Deno.env.get("QD_CURRICULUM_RECEIVER_ENABLED") === "true";

  if (!enabled) {
    return handleShadowReceiver(request, {
      enabled: false,
      keyring: {},
      async reserveNonce() {
        return false;
      },
      async stageArtifact() {
        throw new Error("receiver_disabled");
      },
      async stageRelease() {
        throw new Error("receiver_disabled");
      },
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  let keyring: Record<string, string>;
  try {
    keyring = parseTransportKeyringJson(
      Deno.env.get("QD_CURRICULUM_HMAC_KEYS_JSON"),
    );
  } catch {
    console.error("[qd-curriculum-shadow-receiver] invalid_runtime_keyring");
    return json(500, { ok: false, reason: "runtime_config_error" });
  }

  if (!supabaseUrl || !serviceRoleKey || Object.keys(keyring).length === 0) {
    console.error("[qd-curriculum-shadow-receiver] missing_runtime_config");
    return json(500, { ok: false, reason: "runtime_config_error" });
  }

  const client = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });
  const store = new SupabaseShadowStagingStore(client);

  return handleShadowReceiver(request, {
    enabled: true,
    keyring,
    async reserveNonce(input) {
      const { data, error } = await client.rpc(
        "qd_curriculum_reserve_transport_nonce",
        {
          p_key_id: input.key_id,
          p_nonce: input.nonce,
          p_request_id: input.request_id,
          p_retention_seconds: input.retention_seconds,
        },
      );

      if (error) {
        throw new Error("nonce_reservation_failed");
      }
      return data === true;
    },
    stageArtifact(input) {
      return stagePublicationEnvelopeV1(store, input);
    },
    stageRelease(input) {
      return stageReleaseManifestV1(store, input);
    },
    log(event, fields) {
      console.log("[qd-curriculum-shadow-receiver]", event, fields);
    },
  });
});
