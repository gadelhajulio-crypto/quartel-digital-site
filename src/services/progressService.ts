import { supabase } from '../lib/supabase';
import { Profile } from '../context/AuthContext';

export const startModule = async (moduloId: string, userId: string) => {
    try {
        // Check if entry exists to avoid overwriting existing first_access
        const { data: existing } = await supabase
            .from('recruta_modulos')
            .select('*')
            .eq('recruta_id', userId)
            .eq('modulo_id', moduloId)
            .single();

        if (existing) return; // Already started

        // Create new entry
        const { error } = await supabase
            .from('recruta_modulos')
            .upsert({
                recruta_id: userId,
                modulo_id: moduloId,
                first_access_at: new Date(),
                status: 'in_progress',
            }, { onConflict: 'recruta_id, modulo_id' });

        if (error) throw error;
    } catch (err) {
        console.error('[PROGRESS] Error starting module:', err);
    }
};

export const completeModule = async (moduloId: string, userId: string) => {
    try {
        const { error } = await supabase
            .from('recruta_modulos')
            .update({
                completed_at: new Date(),
                status: 'completed',
            })
            .eq('recruta_id', userId)
            .eq('modulo_id', moduloId);

        if (error) throw error;
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
        const { error } = await supabase
            .from('recruta_licoes')
            .upsert({
                id: undefined, // Let DB generate ID if needed, or composite key
                recruta_id: userId,
                licao_id: lessonId,
                completed_at: new Date(),
            }, { onConflict: 'recruta_id, licao_id' });

        if (error) throw error;
        // console.log('[PROGRESS] Lesson completed:', lessonId);
    } catch (err) {
        console.error('[PROGRESS] Error completing lesson:', err);
    }
};
