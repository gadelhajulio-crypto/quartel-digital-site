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

    // rpc_update_instructor_profile: aceita slug canônico (ramos|rocha|sara)
    console.log('[INSTRUCTOR_RPC_CALL]', {
        selectedInstructor: instructorId,
        p_instructor_profile_id: instructorId,
        source: 'profileService.saveInstructorProfile',
    });
    const { error } = await supabase.rpc('rpc_update_instructor_profile', {
        p_instructor_profile_id: instructorId,
    });

    if (error) {
        throw error;
    }
}
