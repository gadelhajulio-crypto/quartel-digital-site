import { AppState, AppStateStatus } from 'react-native';
import { checkAppLock } from './appLockGuardian';

let isCoordinatorStarted = false;
let isForegroundGuardRunning = false;

/**
 * Coordenador Central de Eventos de Foreground (AppState.active)
 *
 * Responsabilidade: verificar biometria local (AppLock).
 * A validação de sessão institucional (RCC) é feita pelo AppState listener
 * do AuthContext via fetchInstitutionalAuth(), evitando race conditions.
 */
async function handleForegroundState() {
    if (isForegroundGuardRunning) {
        console.log('[AUTH COORDINATOR] Corrida evitada: verificação já em execução.');
        return;
    }

    isForegroundGuardRunning = true;

    try {
        await checkAppLock();
    } catch (error) {
        console.error('[AUTH COORDINATOR] Erro durante verificação de foreground:', error);
    } finally {
        isForegroundGuardRunning = false;
    }
}

/**
 * Inicializa o coordenador central no RootLayout.
 * Centraliza os listeners de AppState para evitar disputas entre guardians.
 */
export function startAuthForegroundCoordinator() {
    if (isCoordinatorStarted) return;
    isCoordinatorStarted = true;

    console.log('[AUTH COORDINATOR] Coordenador de foreground iniciado.');

    AppState.addEventListener('change', (state: AppStateStatus) => {
        if (state === 'active') {
            handleForegroundState();
        }
    });
}
