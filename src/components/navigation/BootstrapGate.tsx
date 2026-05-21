import React, { useCallback, useEffect, useRef, useState } from 'react';
import { ActivityIndicator, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { useRouter } from 'expo-router';
import { useAuth } from '../../context/AuthContext';
import { checkAppBootstrap } from '../../services/bootstrapService';
import { getBillingStatus } from '../../services/billingService';
import { getOnboardingStatus } from '../../services/onboardingService';
import { BootstrapGateContext } from '../../context/BootstrapGateContext';
import { SplashCinematic } from '../splash/SplashCinematic';
import { usePushToken } from '../../hooks/usePushToken';

export type BootstrapState = 'idle' | 'loading' | 'ready' | 'failed';

type GateDestination =
  | 'login'
  | 'mfa'
  | 'locked'
  | 'inactive'
  | 'password_expired'
  | 'onboarding'
  | 'paywall'
  | 'tabs'
  | null;

const DESTINATION_ROUTES: Record<NonNullable<GateDestination>, string> = {
  login: '/(auth)/login',
  mfa: '/(auth)/mfa',
  locked: '/(auth)/locked',
  inactive: '/(auth)/inactive',
  password_expired: '/(auth)/password-expired',
  onboarding: '/(onboarding)/welcome',
  paywall: '/(auth)/paywall',
  tabs: '/(tabs)',
};

export function BootstrapGate({ children }: { children: React.ReactNode }) {
  const { authStatus, loading: authLoading, profile, profileLoading, signOut } = useAuth();
  const router = useRouter();

  const [bootstrapState, setBootstrapState] = useState<BootstrapState>('idle');
  const [destination, setDestination] = useState<GateDestination>(null);
  const [errorMessage, setErrorMessage] = useState('Verifique sua conexão e tente novamente.');
  const [retriggerKey, setRetriggerKey] = useState(0);
  const [splashDone, setSplashDone] = useState(false);

  const lastAuthStatus = useRef(authStatus);
  const redirectedRef = useRef<GateDestination>(null);

  // Referência estável para evitar re-render desnecessário do SplashCinematic
  const handleSplashFinish = useCallback(() => setSplashDone(true), []);

  // Usuário autenticado: pula o cinematic completo
  const forceFinishSplash = !authLoading && authStatus === 'authenticated';

  // Registrar push token após auth + onboarding + billing confirmados (Wave 5a-3)
  usePushToken(bootstrapState === 'ready' && destination === 'tabs');

  console.log('[BOOTSTRAP_GATE] render', {
    authLoading,
    authStatus,
    profileLoading,
    hasProfile: !!profile,
    onboardingConcluido: profile?.onboarding_concluido ?? null,
    bootstrapState,
    destination,
  });

  const retriggerGate = useCallback(() => {
    redirectedRef.current = null;
    setBootstrapState('idle');
    setDestination(null);
    setRetriggerKey((k) => k + 1);
  }, []);

  // Dep estável para profile: evita cancelar bootstraps em andamento quando o
  // objeto profile é atualizado internamente (mudança de referência sem mudança de presença)
  const hasProfile = !!profile;

  // Resolução ordenada: session → identity → bootstrap → onboarding → billing → destino
  useEffect(() => {
    let cancelled = false;

    async function runBootstrap() {
      console.log('[BOOTSTRAP_GATE] start', {
        authLoading,
        authStatus,
        profileLoading,
        hasProfile,
        bootstrapState,
      });

      // 1. Aguarda session e identity resolverem
      if (authLoading || authStatus === 'loading' || profileLoading) {
        console.log('[BOOTSTRAP_GATE] blocked_loading', { authLoading, authStatus, profileLoading });
        return;
      }

      // 2. Sem sessão — redireciona para auth
      if (authStatus !== 'authenticated') {
        console.log('[BOOTSTRAP_GATE] auth_not_authenticated', { authStatus });

        const dest: GateDestination =
          authStatus === 'requires_mfa' ? 'mfa'
            : authStatus === 'account_locked' ? 'locked'
              : authStatus === 'inactive_user' ? 'inactive'
                : authStatus === 'password_expired' ? 'password_expired'
                  : 'login';

        if (!cancelled) {
          setDestination(dest);
          setBootstrapState('ready');
        }
        return;
      }

      // 3. Evita execução concorrente — não bloqueia re-execução após mudança de auth
      if (bootstrapState === 'loading') {
        return;
      }

      setBootstrapState('loading');

      try {
        // 4. Sem identidade — consultar v_onboarding_status (contrato RCC)
        // v_auth_session retornou row válida (authStatus=authenticated), mas
        // v_identidade_recruta não tem row: recruta ainda não concluiu onboarding.
        if (!hasProfile) {
          console.log('[BOOTSTRAP_GATE] no_profile_querying_v_onboarding_status');

          const onboardingStatus = await Promise.race([
            getOnboardingStatus(),
            new Promise<never>((_, reject) =>
              setTimeout(() => reject(new Error('ONBOARDING_STATUS_TIMEOUT')), 10000)
            ),
          ]);

          if (cancelled) return;

          console.log('[BOOTSTRAP_GATE] onboarding_status_result', {
            recruta_id: onboardingStatus?.recruta_id ?? null,
            onboarding_concluido: onboardingStatus?.onboarding_concluido ?? null,
            forca_definida: onboardingStatus?.forca_definida ?? null,
          });

          if (onboardingStatus === null) {
            // Sem row em recrutas: novo recruta pré-onboarding (ex: Google OAuth, conta nova)
            console.log('[BOOTSTRAP_GATE] new_recruta_pre_onboarding_redirect');
            if (!cancelled) {
              setDestination('onboarding');
              setBootstrapState('ready');
            }
            return;
          }

          if (!onboardingStatus.onboarding_concluido) {
            // Recruta existe mas ainda não concluiu onboarding
            console.log('[BOOTSTRAP_GATE] redirect_onboarding');
            if (!cancelled) {
              setDestination('onboarding');
              setBootstrapState('ready');
            }
            return;
          }

          // onboarding_concluido=true sem profile → inconsistência de estado
          if (!cancelled) {
            setErrorMessage('Estado institucional inconsistente. Tente novamente.');
            setBootstrapState('failed');
          }
          return;
        }

        // 5. Bootstrap institucional
        console.log('[BOOTSTRAP_GATE] calling_checkAppBootstrap');

        await Promise.race([
          checkAppBootstrap(),
          new Promise<never>((_, reject) =>
            setTimeout(() => reject(new Error('BOOTSTRAP_TIMEOUT')), 10000)
          ),
        ]);

        if (cancelled) return;

        console.log('[BOOTSTRAP_GATE] bootstrap_ok');

        // 6. Verifica onboarding
        if (!profile?.onboarding_concluido) {
          console.log('[BOOTSTRAP_GATE] redirect_onboarding');
          if (!cancelled) {
            setDestination('onboarding');
            setBootstrapState('ready');
          }
          return;
        }

        // 7. Verifica billing
        console.log('[BOOTSTRAP_GATE] calling_getBillingStatus');

        const billing = await Promise.race([
          getBillingStatus(),
          new Promise<never>((_, reject) =>
            setTimeout(() => reject(new Error('BILLING_TIMEOUT')), 10000)
          ),
        ]);

        if (cancelled) return;

        console.log('[BOOTSTRAP_GATE] billing_ok', { acesso_liberado: billing.acesso_liberado });

        // 8. Decide destino final
        if (!cancelled) {
          setDestination(billing.acesso_liberado ? 'tabs' : 'paywall');
          setBootstrapState('ready');
        }
      } catch (err: any) {
        console.error('[BootstrapGate] Error:', err);
        if (!cancelled) {
          const isTimeout =
            err?.message === 'BOOTSTRAP_TIMEOUT' ||
            err?.message === 'BILLING_TIMEOUT' ||
            err?.message === 'ONBOARDING_STATUS_TIMEOUT';
          setErrorMessage(
            isTimeout
              ? 'A inicialização demorou mais do que o esperado. Tente novamente.'
              : 'Verifique sua conexão e tente novamente.'
          );
          setBootstrapState('failed');
        }
      }
    }

    if (bootstrapState === 'idle' || lastAuthStatus.current !== authStatus) {
      lastAuthStatus.current = authStatus;
      runBootstrap();
    }

    return () => {
      cancelled = true;
    };
  }, [authStatus, authLoading, profileLoading, hasProfile, retriggerKey]); // bootstrapState fora: evita loop

  // Executa navegação quando gate resolve — guarda com ref para garantir UMA execução por destino
  useEffect(() => {
    if (bootstrapState !== 'ready' || !destination) return;
    if (redirectedRef.current === destination) return;

    redirectedRef.current = destination;
    console.log('[BOOTSTRAP_GATE] redirect_phase', { destination });
    router.replace(DESTINATION_ROUTES[destination] as any);
  }, [bootstrapState, destination, router]);

  const showLoadingOverlay = splashDone && (
    authLoading ||
    authStatus === 'loading' ||
    profileLoading ||
    bootstrapState === 'idle' ||
    bootstrapState === 'loading'
  );

  const showErrorOverlay = splashDone && bootstrapState === 'failed';

  // children (<Slot />) é SEMPRE renderizado para manter o outlet de navegação
  // do Expo Router estável. Splash/loading/error aparecem como overlays absolutos.
  return (
    <BootstrapGateContext.Provider value={{ retriggerGate }}>
      {children}

      {/* Splash overlay — cobre tudo enquanto o vídeo toca */}
      {!splashDone && (
        <SplashCinematic
          onFinish={handleSplashFinish}
          forceFinish={forceFinishSplash}
        />
      )}

      {/* Loading overlay — após splash, enquanto auth/bootstrap resolvem */}
      {showLoadingOverlay && (
        <View style={[styles.overlay, styles.center]}>
          <ActivityIndicator size="large" color="#D4AF37" style={{ marginBottom: 20 }} />
          <Text style={styles.title}>Quartel Digital</Text>
          <Text style={styles.subtitle}>Inicializando ambiente institucional...</Text>
        </View>
      )}

      {/* Error overlay — falha no bootstrap */}
      {showErrorOverlay && (
        <View style={[styles.overlay, styles.center]}>
          <Text style={styles.errorTitle}>Não foi possível concluir a inicialização</Text>
          <Text style={styles.errorSubtitle}>{errorMessage}</Text>

          <TouchableOpacity style={styles.button} onPress={retriggerGate}>
            <Text style={styles.buttonText}>Tentar novamente</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.button, styles.logoutButton]}
            onPress={async () => {
              retriggerGate();
              await signOut();
            }}
          >
            <Text style={styles.logoutText}>Sair</Text>
          </TouchableOpacity>
        </View>
      )}
    </BootstrapGateContext.Provider>
  );
}

const styles = StyleSheet.create({
  overlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: '#0F0F13',
    zIndex: 100,
  },
  center: {
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
  },
  title: {
    fontSize: 22,
    fontWeight: 'bold',
    color: '#ECECEC',
    marginBottom: 8,
  },
  subtitle: {
    fontSize: 14,
    color: '#A1A1AA',
    textAlign: 'center',
  },
  errorTitle: {
    fontSize: 20,
    fontWeight: 'bold',
    color: '#EF4444',
    marginBottom: 8,
    textAlign: 'center',
  },
  errorSubtitle: {
    fontSize: 14,
    color: '#A1A1AA',
    textAlign: 'center',
    marginBottom: 32,
  },
  button: {
    backgroundColor: '#D4AF37',
    paddingHorizontal: 24,
    paddingVertical: 14,
    borderRadius: 8,
    width: '100%',
    alignItems: 'center',
    marginBottom: 16,
  },
  buttonText: {
    color: '#0F0F13',
    fontSize: 16,
    fontWeight: 'bold',
  },
  logoutButton: {
    backgroundColor: 'transparent',
    borderWidth: 1,
    borderColor: '#3F3F46',
  },
  logoutText: {
    color: '#A1A1AA',
    fontSize: 16,
    fontWeight: 'bold',
  },
});
