import { supabase } from '../lib/supabase';
import { Profile } from '../context/AuthContext';
import { registerXp } from './xpService';

export const startModule = async (moduloId: string, _userId: string) => {
    try {
        // rpc_start_module: idempotente via ON CONFLICT DO NOTHING no banco
        const { error } = await supabase.rpc('rpc_start_module', {
            p_modulo_id: moduloId,
        });
        if (error) throw error;
    } catch (err) {
        console.error('[PROGRESS] Error starting module:', err);
    }
};

export const completeModule = async (moduloId: string, _userId: string) => {
    try {
        // rpc_complete_module: idempotente via WHERE status != 'completed' no banco
        const { error } = await supabase.rpc('rpc_complete_module', {
            p_modulo_id: moduloId,
        });
        if (error) throw error;

        // Bônus de XP por conclusão de módulo (evento separado)
        await registerXp(500, `Módulo Concluído: ${moduloId}`, moduloId);
    } catch (err) {
        console.error('[PROGRESS] Error completing module:', err);
    }
};

export const checkModuleAccess = (
    moduloId: string,
    profile: Profile
): { allowed: boolean; reason?: 'degustacao_limit' | 'locked' } => {

    // Degustacao Logic: Only Module '1' (Batismo de Fogo) is allowed
    if (profile.tipo_acesso === 'degustacao') {
        if (moduloId !== '1') {
            return { allowed: false, reason: 'degustacao_limit' };
        }
    }

    // Future logic: Check previous module completion
    return { allowed: true };
};

export const completeLesson = async (lessonId: string, userId: string) => {
    try {
        const { error } = await supabase.rpc('complete_lesson', {
            p_recruta_id: userId,
            p_lesson_id: lessonId
        });

        if (error) throw error;

        // XP is handled by RPC now.

    } catch (err) {
        console.error('[PROGRESS] Error completing lesson:', err);
        throw err; // Propagate error for UI handling
    }
};
