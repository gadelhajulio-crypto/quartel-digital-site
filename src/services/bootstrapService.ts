import { supabase } from '../lib/supabase';

/**
 * Service to execute the institutional bootstrap snapshot check.
 * This guarantees the frontend does not proceed to domain screens
 * before the backend institutional environment returns a steady state.
 */
export async function checkAppBootstrap(): Promise<boolean> {
    const { error } = await supabase
        .from('v_app_bootstrap_institucional_rcc')
        .select('*')
        .limit(1);

    if (error) {
        console.error('[BOOTSTRAP] Error validating institutional snapshot:', error);
        throw error;
    }

    return true;
}
