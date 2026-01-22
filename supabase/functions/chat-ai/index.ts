// ========================================
// Edge Function: chat-ai
// ========================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "supabase";
import OpenAI from "openai";

const AGENTS = {
    marinha: 'asst_6TFPlmsULj3fpxArwlkO16nL',
    exercito: 'asst_PL5I6dwKRvHuw6cyy2cNVXHp',
    aeronautica: 'asst_0FpXW9zHkPDVBoIuL5fRi6hX',
};

type ForcaType = keyof typeof AGENTS;

function buildSystemContext(
    instructorProfile: string | null,
    isDegustacao: boolean
): string {
    let personality = '';

    if (instructorProfile === 'estrategico') {
        personality = 'Tom analítico. Explique o porquê das regras.';
    } else if (instructorProfile === 'didatico') {
        personality = 'Tom claro, paciente e educativo.';
    } else {
        personality = 'Tom direto, disciplinado e objetivo.';
    }

    let scopeRule = '';

    if (isDegustacao) {
        scopeRule = `
RESTRIÇÃO DE ESCOPO:
Modo degustação ativo.
Responda APENAS sobre regulamentos disciplinares,
funcionamento do Quartel Digital e conteúdos disponíveis na degustação.
Se a pergunta sair desse escopo, informe de forma institucional
que o acesso completo é necessário para aprofundamento.
`;
    }

    return `
INSTRUÇÕES DO INSTRUTOR:
${personality}

${scopeRule}

Mantenha linguagem institucional.
Não use emojis.
Não invente informações.
`;
}

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req: Request) => {
    // Tratamento de CORS (Preflight)
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders });
    }

    // Validação de método HTTP
    if (req.method !== 'POST') {
        return new Response('Method not allowed', {
            status: 405,
            headers: corsHeaders
        });
    }

    try {
        const { message, threadId, userId, isDegustacao } = await req.json();

        // Validação de parâmetros obrigatórios
        if (!message || !userId) {
            return new Response(
                JSON.stringify({ error: 'Campos obrigatórios: message, userId' }),
                {
                    status: 400,
                    headers: { ...corsHeaders, "Content-Type": "application/json" }
                }
            );
        }

        const supabaseUrl = Deno.env.get('SUPABASE_URL');
        const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
        const openaiKey = Deno.env.get('OPENAI_API_KEY');

        if (!supabaseUrl || !supabaseKey || !openaiKey) {
            throw new Error('Variáveis de ambiente não configuradas');
        }

        const supabase = createClient(supabaseUrl, supabaseKey);
        const openai = new OpenAI({ apiKey: openaiKey });

        const { data: profile, error } = await supabase
            .from('profiles')
            .select('forca, instructor_profile_id')
            .eq('id', userId)
            .single();

        if (error || !profile?.forca) {
            return new Response(
                JSON.stringify({ error: 'Perfil inválido ou força não definida' }),
                {
                    status: 400,
                    headers: { ...corsHeaders, "Content-Type": "application/json" }
                }
            );
        }

        // Validação se a força existe nos AGENTS
        const forcaKey = profile.forca as ForcaType;
        if (!AGENTS[forcaKey]) {
            console.warn(`Força desconhecida: ${profile.forca}. Usando Marinha como fallback.`);
        }

        const agentId = AGENTS[forcaKey] ?? AGENTS.marinha;

        let finalThreadId = threadId;
        if (!finalThreadId) {
            const thread = await openai.beta.threads.create();
            finalThreadId = thread.id;
        }

        await openai.beta.threads.messages.create(finalThreadId, {
            role: 'user',
            content: message,
        });

        const systemContext = buildSystemContext(
            profile.instructor_profile_id,
            !!isDegustacao
        );

        const run = await openai.beta.threads.runs.create(finalThreadId, {
            assistant_id: agentId,
            additional_instructions: systemContext,
        });

        return new Response(
            JSON.stringify({ threadId: finalThreadId, runId: run.id }),
            {
                headers: {
                    ...corsHeaders,
                    "Content-Type": "application/json"
                }
            }
        );

    } catch (e) {
        const error = e as Error;
        console.error('[CHAT AI ERROR]:', error);
        return new Response(
            JSON.stringify({ error: error.message || 'Erro interno do servidor' }),
            {
                status: 500,
                headers: {
                    ...corsHeaders,
                    "Content-Type": "application/json"
                }
            }
        );
    }
});
