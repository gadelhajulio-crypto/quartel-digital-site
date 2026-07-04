import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { provisionRecruta } from "./core.ts";

// NOTA: função REMOVIDA de produção (decisão 2026-07-04, achado A-9 — sem guard de
// autorização). Esta fonte segue versionada apenas como base para um eventual redeploy
// futuro pela Opção B (guard admin + verify_jwt). NÃO reativar sem o guard.
// A correção do A-10 vive em ./core.ts e foi validada por teste isolado (../create-recruta/test.mts),
// NÃO por integração real — validação de integração completa é pré-requisito de qualquer redeploy.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, authorization, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const projectUrl = Deno.env.get("PROJECT_URL");
  const serviceRoleKey = Deno.env.get("SERVICE_ROLE_KEY");

  if (!projectUrl || !serviceRoleKey) {
    console.error("ENV_MISSING", { projectUrl, serviceRoleKey });
    return new Response(
      JSON.stringify({ error: "Supabase env vars não configuradas" }),
      { status: 500, headers: corsHeaders }
    );
  }

  try {
    const body = await req.json();
    const supabase = createClient(projectUrl, serviceRoleKey);

    const result = await provisionRecruta(supabase, body);

    if (!result.ok) {
      return new Response(
        JSON.stringify({ error: result.error }),
        { status: result.status, headers: corsHeaders }
      );
    }

    // Missão inicial não-fatal (comportamento original preservado): só sinaliza.
    if (!result.missao_atribuida) {
      console.error("MISSAO_ERROR", { recruta_id: result.recruta_id });
    }

    return new Response(
      JSON.stringify({ success: true, auth_id: result.auth_id, recruta_id: result.recruta_id }),
      { status: 200, headers: corsHeaders }
    );
  } catch (err: any) {
    console.error("ERRO_CREATE_RECRUTA", err);
    return new Response(
      JSON.stringify({ error: err.message ?? "internal error" }),
      { status: 500, headers: corsHeaders }
    );
  }
});
