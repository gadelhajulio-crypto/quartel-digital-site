import { supabase } from '../lib/supabase';
import { Profile } from '../context/AuthContext';
import { registerXp } from './xpService';

// ─── P1-M1 Sprint 2 Fase 2 ───────────────────────────────────────────────────
// Fallback flag: DEV ONLY. Flip para true para reverter ao complete_lesson sem
// alterar backend. Nunca ativar em produção — a guarda __DEV__ garante isso.
const USE_LEGACY_COMPLETE_LESSON = false;
// ─────────────────────────────────────────────────────────────────────────────

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
    // userId retido na assinatura para compatibilidade com callers existentes.
    // Não é mais enviado ao banco — identidade derivada de auth.uid() no servidor (P1-M1.1).

    // Rollback rápido em DEV: flip USE_LEGACY_COMPLETE_LESSON = true no topo do arquivo.
    if (__DEV__ && USE_LEGACY_COMPLETE_LESSON) {
        try {
            const { error } = await supabase.rpc('complete_lesson', {
                p_recruta_id: userId,
                p_lesson_id: lessonId,
            });
            if (error) throw error;
        } catch (err) {
            console.error('[PROGRESS] [LEGACY] Error completing lesson:', err);
            throw err;
        }
        return;
    }

    try {
        const { data, error } = await supabase.rpc('rpc_complete_lesson', {
            p_lesson_id: lessonId,
        });

        if (__DEV__) {
            console.info('[P1-M1]', 'rpc_complete_lesson', data);
        }

        if (error) {
            if (error.code === '42501') {
                // Guarda 1: sessão não autenticada — não deve ocorrer se o app
                // gerencia o JWT corretamente. Logar para diagnóstico.
                console.error('[PROGRESS] rpc_complete_lesson: unauthenticated (42501)');
            } else if (error.code === '22023') {
                // Guarda 2/3: perfil incompleto ou aula não encontrada.
                console.error('[PROGRESS] rpc_complete_lesson: invalid_parameter (22023)', lessonId);
            } else {
                console.error('[PROGRESS] rpc_complete_lesson error:', error.code, error.message);
            }
            throw error;
        }

    } catch (err) {
        console.error('[PROGRESS] Error completing lesson:', err);
        throw err; // Propagate error for UI handling
    }
};
