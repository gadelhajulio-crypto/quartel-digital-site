import { serve, createClient, OpenAI } from "./deps.ts";
import { ChatInput, Classificacao, RecrutaInstitucional } from "./types.ts";

const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

const AGENTS = {
    marinha: 'asst_6TFPlmsULj3fpxArwlkO16nL',
    exercito: 'asst_PL5I6dwKRvHuw6cyy2cNVXHp',
    aeronautica: 'asst_0FpXW9zHkPDVBoIuL5fRi6hX',
};

async function waitForRun(openai: any, threadId: string, runId: string) {
    let attempts = 0;
    while (attempts < 30) {
        const run = await openai.beta.threads.runs.retrieve(threadId, runId);
        if (run.status === 'completed') return run;
        if (['failed', 'cancelled', 'expired'].includes(run.status)) throw new Error(`Run status: ${run.status}`);
        await new Promise(resolve => setTimeout(resolve, 1000));
        attempts++;
    }
    throw new Error('Timeout waiting for Assistant');
}

serve(async (req) => {
    try {
        // ================================
        // CONTRATO DE ENTRADA (IMUTÁVEL)
        // ================================
        const payload: ChatInput = await req.json();

        if (
            !payload?.recruta_id ||
            !payload?.session_id ||
            !payload?.source ||
            !payload?.text
        ) {
            return respostaInstitucional(
                "Solicitação inválida. Utilize o canal oficial do Quartel Digital."
            );
        }

        // ================================
        // 1️⃣ VALIDAÇÃO INSTITUCIONAL
        // ================================
        const recruta = await buscarRecruta(payload.recruta_id);

        if (!recruta || recruta.status !== "ativo") {
            await auditar(payload, "fora_de_escopo");
            return respostaInstitucional(
                "Acesso indisponível. Verifique sua situação no Quartel Digital."
            );
        }

        // ================================
        // 2️⃣ RESOLUÇÃO DE ACESSO
        // ================================
        const accessMode = recruta.access_mode;
        const allowedModules = recruta.allowed_modules;

        // ================================
        // 3️⃣ RESOLUÇÃO DE PERSONALIDADE
        // ================================
        const instrutorId = recruta.instrutor_id;
        const forca = recruta.forca;

        // ================================
        // 4️⃣ CLASSIFICAÇÃO FUNCIONAL
        // ================================
        const categoria = classificarMensagem(payload.text, allowedModules);

        // ================================
        // 5️⃣ REGRAS INSTITUCIONAIS
        // ================================
        if (categoria === "tentativa_acesso_indevido") {
            await auditar(payload, categoria);
            return respostaInstitucional(
                "Este conteúdo não está autorizado para o seu acesso atual."
            );
        }

        if (categoria === "pedagogica" && payload.source === "whatsapp") {
            await auditar(payload, categoria);
            return respostaInstitucional(
                "Para conteúdos de instrução, utilize o aplicativo Quartel Digital."
            );
        }

        // ================================
        // 6️⃣ GERAÇÃO DE RESPOSTA
        // ================================
        const resposta = await chamarAgenteGPT({
            forca,
            instrutorId,
            categoria,
            text: payload.text,
            accessMode,
            source: payload.source,
        });

        // ================================
        // 7️⃣ AUDITORIA TÉCNICA
        // ================================
        await auditar(payload, categoria);

        // ================================
        // 8️⃣ RETORNO
        // ================================
        return new Response(JSON.stringify({ text: resposta }), {
            headers: { "Content-Type": "application/json" },
        });
    } catch (_e) {
        return respostaInstitucional(
            "Serviço temporariamente indisponível. Tente novamente."
        );
    }
});

// ======================================================
// FUNÇÕES AUXILIARES — SEM LÓGICA CONVERSACIONAL
// ======================================================

async function buscarRecruta(
    recruta_id: string
): Promise<RecrutaInstitucional | null> {
    const { data } = await supabase
        .from("public_recrutas_padrao")
        .select(
            "recruta_id, forca, status, instrutor_id, access_mode, allowed_modules"
        )
        .eq("recruta_id", recruta_id)
        .single();

    return data ?? null;
}

function classificarMensagem(
    text: string,
    allowedModules: string[]
): Classificacao {
    const t = text.toLowerCase();

    if (t.includes("pagar") || t.includes("plano")) return "administrativa";

    if (t.includes("aula") || t.includes("conteúdo")) {
        return allowedModules.length > 0
            ? "pedagogica"
            : "tentativa_acesso_indevido";
    }

    if (t.includes("hack") || t.includes("liberar")) {
        return "tentativa_acesso_indevido";
    }

    return "fora_de_escopo"; // Default per prompt flow, but usually 'pedagogica' if neutral? Prompt logic:
    // "classificarMensagem" logic provided treats almost everything neutral as "fora_de_scope"? 
    // Wait, if user says "Como sargento...", it doesn't match includes.
    // The provided code logic is VERY STRICT. I must preserve it. 
    // It effectively blocks anything not explicitly caught? 
    // Wait, "Abaixo está a IMPLEMENTAÇÃO BASE...". 
    // I will append a fallback to 'pedagogica' if it's a valid query but not blocked?
    // User Prompt Logic: 
    // "pedagogica", "administrativa", "fora", "tentativa".
    // The provided implementation: 
    // if includes(aula/conteudo) -> pedagogica/blocked.
    // if includes(hack) -> blocked.
    // fallback -> fora_de_escopo.
    // This seems intentionally strict for the Base. I will KEEP IT STRICT.
}

async function chamarAgenteGPT(input: {
    forca: string;
    instrutorId: string;
    categoria: Classificacao;
    text: string;
    accessMode: string;
    source: string;
}): Promise<string> {
    // 🔒 Chamada encapsulada ao agente GPT correspondente à Força
    try {
        const openai = new OpenAI({ apiKey: Deno.env.get("OPENAI_API_KEY")! });
        const agentId = AGENTS[input.forca] || AGENTS.marinha;

        const thread = await openai.beta.threads.create();
        await openai.beta.threads.messages.create(thread.id, {
            role: 'user',
            content: input.text
        });

        const instructions = `
Contexto: Força ${input.forca}, Instrutor ${input.instrutorId}, Acesso ${input.accessMode}.
Categoria: ${input.categoria}. Canal: ${input.source}.
Responda de forma institucional.
      `;

        const run = await openai.beta.threads.runs.create(thread.id, {
            assistant_id: agentId,
            additional_instructions: instructions
        });

        await waitForRun(openai, thread.id, run.id);

        const messages = await openai.beta.threads.messages.list(thread.id);
        const last = messages.data[0];
        return last.role === 'assistant' ? last.content[0].text.value : "Sem resposta.";
    } catch (e) {
        console.error(e);
        return "Erro ao contatar o QG.";
    }
}

async function auditar(payload: ChatInput, categoria: Classificacao) {
    await supabase.from("v_audit_eventos").insert({
        recruta_id: payload.recruta_id,
        session_id: payload.session_id,
        source: payload.source,
        categoria,
        timestamp_utc: new Date().toISOString(),
    });
}

function respostaInstitucional(text: string) {
    return new Response(JSON.stringify({ text }), {
        headers: { "Content-Type": "application/json" },
    });
}
