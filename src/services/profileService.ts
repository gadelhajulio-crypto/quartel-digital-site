import { supabase } from '../lib/supabase';
import { InstructorProfileId } from '../constants/instructors';

export async function saveInstructorProfile(
    instructorId: InstructorProfileId
) {
    const {
        data: { user },
        error: authError,
    } = await supabase.auth.getUser();

    if (authError || !user) {
        throw new Error('Usuário não autenticado');
    }

    // rpc_set_instructor_profile: SECURITY DEFINER usa auth.uid() internamente
    const { error } = await supabase.rpc('rpc_set_instructor_profile', {
        p_instructor_id: instructorId,
    });

    if (error) {
        throw error;
    }
}
