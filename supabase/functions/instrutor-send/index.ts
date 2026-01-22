import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.7.1";
import OpenAI from "https://esm.sh/openai@4.20.1";

const AGENTS = {
  marinha: 'asst_6TFPlmsULj3fpxArwlkO16nL',
  exercito: 'asst_PL5I6dwKRvHuw6cyy2cNVXHp', // Placeholder ID
  aeronautica: 'asst_0FpXW9zHkPDVBoIuL5fRi6hX', // Placeholder ID
};

// CORS verification
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

async function waitForRun(openai: any, threadId: string, runId: string) {
  let attempts = 0;
  while (attempts < 30) { // Max ~30-60s
    const run = await openai.beta.threads.runs.retrieve(threadId, runId);
    if (run.status === 'completed') {
      return run;
    }
    if (run.status === 'failed' || run.status === 'cancelled' || run.status === 'expired') {
      throw new Error(`Run ended with status: ${run.status}`);
    }
    await new Promise(resolve => setTimeout(resolve, 1000));
    attempts++;
  }
  throw new Error('Timeout waiting for Assistant response');
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { message, context } = await req.json();

    // 1. Validate Payload
    if (!message || !context || !context.user_id || !context.force) {
      throw new Error('Payload inválido ou incompleto.');
    }

    const { user_id, recruta_id, force, access_mode, instructor_profile_id } = context;

    // 2. Setup Clients
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const openaiKey = Deno.env.get('OPENAI_API_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseKey);
    const openai = new OpenAI({ apiKey: openaiKey });

    // 3. Determine Agent
    const forceKey = force.toLowerCase();
    const agentId = AGENTS[forceKey] || AGENTS.marinha;

    // 4. Create Thread & Run
    const thread = await openai.beta.threads.create();
    await openai.beta.threads.messages.create(thread.id, {
      role: 'user',
      content: message
    });

    const isDegustacao = access_mode === 'restricted';
    const instructions = `
Contexto do Aluno:
Força: ${force}
Perfil de Instrutor: ${instructor_profile_id || 'padrão'}
Modo de Acesso: ${isDegustacao ? 'DEGUSTAÇÃO (Restrito)' : 'COMPLETO'}

${isDegustacao ? 'ATENÇÃO: Responda APENAS sobre conteúdos gratuitos. Se o aluno perguntar sobre conteúdo pago, negue educadamente e sugira o plano completo.' : ''}
    `;

    const run = await openai.beta.threads.runs.create(thread.id, {
      assistant_id: agentId,
      additional_instructions: instructions,
    });

    // 5. Wait for Response (Sync for Audit)
    await waitForRun(openai, thread.id, run.id);

    // 6. Get Messages
    const messages = await openai.beta.threads.messages.list(thread.id);
    const lastMsg = messages.data[0];
    const replyText = lastMsg.role === 'assistant' ? lastMsg.content[0].text.value : "Sem resposta.";

    // 7. AUDIT LOG (Internal)
    // Determine category based on access mode and simple heuristics (logging metadata only)
    let category = 'answered_within_scope';
    if (isDegustacao && (replyText.includes('acesso completo') || replyText.includes('plano'))) {
      category = 'blocked_by_scope';
    }

    const { error: auditError } = await supabase.from('chat_audit_log').insert({
      user_id,
      recruta_id: recruta_id || user_id,
      force,
      instructor_profile_id,
      access_mode,
      interaction_type: 'question',
      response_category: category,
      source: 'mobile_app',
      agent: `instrutor_${forceKey}`,
      // No message content logged!
    });

    if (auditError) {
      console.error('Audit Log Failed:', auditError);
      // We do not fail the request, just log error internally
    }

    return new Response(
      JSON.stringify({ reply: replyText }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err: any) {
    console.error('Edge Function Error:', err);
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});