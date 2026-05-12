import { supabase } from '../lib/supabase';

export interface IEAData {
    score: number;
    concept: string; // 'Regular' | 'Alta Performance' | 'Excelência'
    updated_at: string;
}

export async function getCurrentIEA(recrutaId: string): Promise<IEAData | null> {
    const { data, error } = await supabase
        .from('v_iea_atual_v2')
        .select('score, concept, updated_at')
        .eq('recruta_id', recrutaId)
        .single();

    if (error) {
        // Se não encontrar (PGRST116), retorna null para exibir "Em apuração"
        if (error.code === 'PGRST116') return null;

        console.error('Error fetching IEA:', error);
        return null; // Fallback seguro
    }

    return data as IEAData;
}

export async function checkIEAAuditAvailability(): Promise<boolean> {
    // Tenta fazer um select simples (limit 1) para ver se a view existe e é acessível
    const { error, count } = await supabase
        .from('v_iea_audit')
        .select('*', { count: 'exact', head: true }); // HEAD request para ser leve

    if (error) {
        // Se der erro 404 (PGRST116 ou similar de tabela não encontrada), retorna false
        return false;
    }
    return true;
}
