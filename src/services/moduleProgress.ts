import { supabase } from '../lib/supabase';

export type ModuleProgress = {
    completed: number;
    total: number;
};

export async function getModuleProgress(
    recrutaId: string,
    moduloId: string
): Promise<ModuleProgress> {
    // Using an array to receive the single row returned by the RPC
    const { data, error } = await supabase.rpc('module_progress', {
        p_recruta_id: recrutaId,
        p_modulo_id: moduloId,
    });

    if (error) {
        console.error('Error fetching module progress:', error);
        return { completed: 0, total: 0 };
    }

    // RPC returns an array of objects (rows) even for single return
    if (data && Array.isArray(data) && data.length > 0) {
        return {
            completed: data[0].completed,
            total: data[0].total
        };
    }

    // Fallback if data structure is direct object (depends on RPC definition/client version)
    // but usually table return types are arrays.
    if (data && !Array.isArray(data)) {
        return {
            completed: (data as any).completed,
            total: (data as any).total
        };
    }

    return { completed: 0, total: 0 };
}
