import { supabase } from '../lib/supabase';

let isGuardianStarted = false;
let isChecking = false;

/**
 * Função principal do Session Guardian:
 * 1. Obter a sessão técnica.
 * 2. Se nula, retorna silenciosamente.
 * 3. Consulta `v_auth_session`.
 * 4. Avalia a coluna `session_revoked_reason`.
 */
export async function checkInstitutionalSession(): Promise<boolean> {
    if (isChecking) return true;

    try {
        isChecking = true;

        // 1. Obter sessão técnica
        const { data: { session }, error: sessionError } = await supabase.auth.getSession();

        // 2. Se session == null ou erro na obtenção técnica, retornar
        if (sessionError || !session) return true;

        // 3. Consultar view institucional
        const { data, error: viewError } = await supabase
            .from('v_auth_session')
            .select('*')
            .single();

        if (viewError || !data) return true;

        // 4. Interpretar a resposta do gateway institucional
        const revokedReason = data.session_revoked_reason;
        if (revokedReason && revokedReason !== 'none') {
            console.log('[SESSION GUARDIAN] Sessão revogada institucionalmente! Motivo:', revokedReason);
            // Executar: supabase.auth.signOut() e deixar o AuthContext redirecionar
            await supabase.auth.signOut();
            return false;
        }

        return true;
    } catch (e) {
        console.warn('[SESSION GUARDIAN] Falha ao verificar sessão institucional', e);
        return true;
    } finally {
        isChecking = false;
    }
}

/**
 * Start Session Guardian implementa triggers de validação institucional contínua
 * aderente aos princípios de RCC v0.3.
 */
export function startSessionGuardian() {
    if (isGuardianStarted) return;
    isGuardianStarted = true;

    console.log('[SESSION GUARDIAN] Iniciando monitoramento estrito.');

    // Heartbeat a cada 90s para detectar revogações remotas de sessão
    setInterval(() => {
        console.log('[SESSION GUARDIAN] Trigger: Hearbeat 90s...');
        checkInstitutionalSession();
    }, 90 * 1000);
}
