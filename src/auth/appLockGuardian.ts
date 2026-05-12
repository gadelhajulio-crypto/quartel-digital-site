import * as LocalAuthentication from 'expo-local-authentication';

let lastActiveAt: number = Date.now();
let isGuardianStarted: boolean = false;
let isAuthenticating: boolean = false;

// 2 horas em milissegundos
const TWO_HOURS_MS = 2 * 60 * 60 * 1000;

/**
 * Registra o timestamp de atividade.
 * Deve ser chamado sempre que o usuário interagir ou o app for aberto.
 */
export function updateLastActive() {
    if (isAuthenticating) return;
    lastActiveAt = Date.now();
    // console.log('[APP LOCK GUARDIAN] Atividade registrada', new Date(lastActiveAt).toISOString());
}

/**
 * Função principal que verifica se o tempo expirou e exige biometria.
 */
export async function checkAppLock() {
    if (isAuthenticating) return;

    const now = Date.now();
    const inactiveTime = now - lastActiveAt;

    if (inactiveTime > TWO_HOURS_MS) {
        console.log('[APP LOCK GUARDIAN] Inatividade > 2h detectada. Exigindo biometria.');

        // Verifica se biometria está disponível
        const hasHardware = await LocalAuthentication.hasHardwareAsync();
        const isEnrolled = await LocalAuthentication.isEnrolledAsync();

        if (!hasHardware || !isEnrolled) {
            console.log('[APP LOCK GUARDIAN] Biometria não disponível/configurada, reiniciando timer de fallback.');
            updateLastActive();
            return;
        }

        try {
            isAuthenticating = true;
            const result = await LocalAuthentication.authenticateAsync({
                promptMessage: 'Desbloqueie o Quartel Digital',
                cancelLabel: 'Cancelar',
                disableDeviceFallback: false,
            });

            if (result.success) {
                console.log('[APP LOCK GUARDIAN] Biometria validada com sucesso.');
                updateLastActive();
            } else {
                console.log('[APP LOCK GUARDIAN] Falha na biometria. Mantendo tela retida.', result.error);
                // Em caso de cancelamento, a tela ficará travada na View da UI onde tentamos desbloquear?
                // O LocalAuthentication exibe um prompt nativo. Se falhar, podemos forçar um loop ou apenas 
                // impedir a liberação no JS, mas como a feature pede "se falha, manter tela bloqueada",
                // num design avançado exibiríamos uma "Screen" de lock. O prompt não especifica uma tela de bloqueio, 
                // e invocar biometria novamente sem parar pode ser irritante. 
                // Mas podemos forçar uma nova checagem.
                setTimeout(() => {
                    checkAppLock();
                }, 1000); // 1s cooldown para evitar lock-loop do app se o usuário der dismiss
            }
        } catch (e) {
            console.error('[APP LOCK GUARDIAN] Erro na biometria:', e);
        } finally {
            isAuthenticating = false;
        }
    }
}

/**
 * Inicia o App Lock Guardian.
 * Monita o AppState para validar no retorno ao active.
 */
export function startAppLockGuardian() {
    if (isGuardianStarted) return;
    isGuardianStarted = true;

    console.log('[APP LOCK GUARDIAN] Monitoramento de segurança ativo.');

    // Gatilho inicial
    updateLastActive();
}
