import { supabase } from '../lib/supabase';

export interface EliteStatus {
    elegivel: boolean;
    regularidade: number; // 0-100
    mensagem?: string; // Motivo ou texto de apoio
}

export async function getEliteStatus(recrutaId: string): Promise<EliteStatus | null> {
    const { data, error } = await supabase
        .from('v_elegibilidade_elite_v2')
        .select('recruta_id, elegivel_elite, regularidade_percentual, motivos_negacao')
        .eq('recruta_id', recrutaId)
        .single();

    if (error) {
        if (error.code !== 'PGRST116') {
            console.warn('[Elite] Dados institucionais temporariamente indisponíveis.');
        }
        return null;
    }

    return {
        elegivel: data.elegivel_elite,
        regularidade: data.regularidade_percentual ?? 0,
        mensagem: Array.isArray(data.motivos_negacao) && data.motivos_negacao.length > 0
            ? data.motivos_negacao.join(', ')
            : undefined
    };
}

export interface CycleClassification {
    recruta_id: string;
    ciclo_id: string;
    iea_score: number | null;
    xp_normalizado: number | null;
    score_final: number | null;
    status_regularidade: string | null;
    regularidade_percentual: number | null;
    hierarquia_atual: string | null;
}

export async function getCycleClassification(
    recrutaId: string,
    cycleId?: string
): Promise<CycleClassification | null> {
    let query = supabase
        .from('v_classificacao_final_ciclo_v2')
        .select(`
            recruta_id,
            ciclo_id,
            iea_score,
            xp_normalizado,
            score_final,
            status_regularidade,
            regularidade_percentual,
            hierarquia_atual
        `)
        .eq('recruta_id', recrutaId);

    if (cycleId) {
        query = query.eq('ciclo_id', cycleId);
    } else {
        query = query.order('ciclo_id', { ascending: false }).limit(1);
    }

    const { data, error } = await query.single();

    if (error) {
        if (error.code !== 'PGRST116') {
            console.warn('[Cycle] Dados institucionais temporariamente indisponíveis.');
        }
        return null;
    }

    return data as CycleClassification;
}
