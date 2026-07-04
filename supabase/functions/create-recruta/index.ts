import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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
    const { email, name, senha, forca = "marinha" } = await req.json();

    if (!email || !senha) {
      return new Response(
        JSON.stringify({ error: "Email e senha são obrigatórios" }),
        { status: 400, headers: corsHeaders }
      );
    }

    const supabase = createClient(projectUrl, serviceRoleKey);

    const { data, error } = await supabase.auth.admin.createUser({
      email,
      password: senha,
      email_confirm: true,
    });

    if (error) {
      console.error("AUTH_ERROR", error);
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 400, headers: corsHeaders }
      );
    }

    const { error: dbError } = await supabase
      .from("recrutas")
      .insert({
        auth_id: data.user.id,
        email,
        nome: name,
        forca,
        patente: "Recruta",
        plano: "basico",
        status: "ativo",
      });
// Atribuir missão inicial de onboarding
const { error: missaoError } = await supabase.rpc(
  "atribuir_missao_inicial",
  {
    p_recruta_id: data.user.id,
  }
);

if (missaoError) {
  console.error("MISSAO_ERROR", missaoError);
}

    if (dbError) {
      console.error("DB_ERROR", dbError);
      return new Response(
        JSON.stringify({ error: dbError.message }),
        { status: 400, headers: corsHeaders }
      );
    }

    return new Response(
      JSON.stringify({ success: true, auth_id: data.user.id }),
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
