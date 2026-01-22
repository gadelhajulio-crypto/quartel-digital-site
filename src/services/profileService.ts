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

    const { error } = await supabase
        .from('profiles')
        .update({
            instructor_profile_id: instructorId,
        })
        .eq('id', user.id);

    if (error) {
        throw error;
    }
}
