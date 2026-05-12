import { supabase } from '../lib/supabase';

export interface ActiveSession {
    session_id: string;
    device_name: string;
    last_seen_at: string;
    is_current: boolean;
}

export async function getActiveSessions(): Promise<ActiveSession[]> {
    const { data, error } = await supabase
        .from('v_auth_active_sessions')
        .select('*')
        .order('last_seen_at', { ascending: false });

    if (error) {
        throw error;
    }

    return data as ActiveSession[];
}

export async function revokeSession(sessionId: string): Promise<void> {
    const { error } = await supabase.rpc('rpc_auth_revoke_client_session', {
        p_session_id: sessionId
    });

    if (error) {
        throw error;
    }
}
