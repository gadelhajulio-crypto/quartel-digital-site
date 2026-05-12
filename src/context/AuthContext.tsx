import React, { createContext, useContext, useEffect, useRef, useState } from 'react';
import { AppState, AppStateStatus } from 'react-native';
import * as SecureStore from 'expo-secure-store';
import * as Crypto from 'expo-crypto';
import { Session, User } from '@supabase/supabase-js';
import { AuthStatus, SessionRevokedReason } from '../types/auth';
import { supabase } from '../lib/supabase';
import { startSessionGuardian } from '../auth/sessionGuardian';

export type Profile = {
  id: string;
  nome: string;
  nome_guerra?: string;
  patente: string;
  forca: 'marinha' | 'exercito' | 'aeronautica';
  nivel_atual: number;
  xp: number;
  avatar_url?: string;
  instructor_profile_id?: 'objetivo' | 'estrategico' | 'didatico' | null;
  tipo_acesso: 'degustacao' | 'completo';
  onboarding_concluido: boolean;
  ativo: boolean;
};

interface AuthContextType {
  loginBannerReason: SessionRevokedReason | null;
  authStatus: AuthStatus;
  authSession: any | null;
  session: Session | null;
  user: User | null;
  profile: Profile | null;
  loading: boolean;
  profileLoading: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  refetchProfile: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

const CLIENT_INSTANCE_ID_KEY = 'client_instance_id';

function parseRccVersion(authContractVersion: string): { major: number; minor: number } | null {
  const cleaned = authContractVersion.replace(/^RCC-/, '').trim();
  const parts = cleaned.split('.');
  if (parts.length < 2) return null;

  const major = Number(parts[0]);
  const minor = Number(parts[1]);
  if (!Number.isFinite(major) || !Number.isFinite(minor)) return null;

  return { major, minor };
}

function isAtLeastRcc03(authContractVersion: string): boolean {
  const v = parseRccVersion(authContractVersion);
  if (!v) return false;
  return v.major > 0 || (v.major === 0 && v.minor >= 3);
}

async function getOrCreateClientInstanceId(): Promise<string> {
  const existing = await SecureStore.getItemAsync(CLIENT_INSTANCE_ID_KEY);
  if (existing) return existing;

  const generated = Crypto.randomUUID();
  await SecureStore.setItemAsync(CLIENT_INSTANCE_ID_KEY, generated);
  return generated;
}

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [loginBannerReason, setLoginBannerReason] = useState<SessionRevokedReason | null>(null);
  const [authStatus, setAuthStatus] = useState<AuthStatus>('loading');
  const [authSession, setAuthSession] = useState<any | null>(null);
  const [session, setSession] = useState<Session | null>(null);

  const [profile, setProfile] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);
  const [profileLoading, setProfileLoading] = useState(false);

  const sessionRef = useRef<string | null>(null);
  const clientInstanceIdRef = useRef<string | null>(null);
  const fetchingInstitutionalAuthRef = useRef(false);

  const authStatusRef = useRef<AuthStatus>('loading');
  const loginBannerReasonRef = useRef<SessionRevokedReason | null>(null);
  const authSessionRef = useRef<any | null>(null);
  const sessionStateRef = useRef<Session | null>(null);
  const profileRef = useRef<Profile | null>(null);
  const loadingRef = useRef<boolean>(true);
  const profileLoadingRef = useRef<boolean>(false);

  useEffect(() => {
    authStatusRef.current = authStatus;
  }, [authStatus]);

  useEffect(() => {
    loginBannerReasonRef.current = loginBannerReason;
  }, [loginBannerReason]);

  useEffect(() => {
    authSessionRef.current = authSession;
  }, [authSession]);

  useEffect(() => {
    sessionStateRef.current = session;
  }, [session]);

  useEffect(() => {
    profileRef.current = profile;
  }, [profile]);

  useEffect(() => {
    loadingRef.current = loading;
  }, [loading]);

  useEffect(() => {
    profileLoadingRef.current = profileLoading;
  }, [profileLoading]);

  async function debugSessionSnapshot(label: string) {
    try {
      const { data, error } = await supabase.auth.getSession();

      console.log('[H1_GET_SESSION]', {
        label,
        clientInstanceId: clientInstanceIdRef.current,
        error: error
          ? {
            message: error.message,
            name: error.name,
            status: (error as any)?.status ?? null,
          }
          : null,
        session: data?.session
          ? {
            user_id: data.session.user?.id ?? null,
            email: data.session.user?.email ?? null,
            expires_at: data.session.expires_at ?? null,
            expires_in: data.session.expires_in ?? null,
            token_type: data.session.token_type ?? null,
            access_token_present: !!data.session.access_token,
            refresh_token_present: !!data.session.refresh_token,
          }
          : null,
        authStatus_snapshot: authStatusRef.current,
        loginBannerReason_snapshot: loginBannerReasonRef.current,
        hasAuthSession_snapshot: !!authSessionRef.current,
        authSession_snapshot: authSessionRef.current
          ? {
            auth_id: authSessionRef.current.auth_id ?? null,
            session_revoked_reason: authSessionRef.current.session_revoked_reason ?? null,
            requires_mfa: authSessionRef.current.requires_mfa ?? null,
            account_locked: authSessionRef.current.account_locked ?? null,
            inactive_user: authSessionRef.current.inactive_user ?? null,
            password_expired: authSessionRef.current.password_expired ?? null,
          }
          : null,
        sessionRef_snapshot: sessionRef.current,
      });
    } catch (e: any) {
      console.log('[H1_GET_SESSION_EXCEPTION]', {
        label,
        clientInstanceId: clientInstanceIdRef.current,
        message: e?.message ?? 'unknown_error',
      });
    }
  }

  function debugStateSnapshot(label: string) {
    console.log('[H1_STATE]', {
      label,
      clientInstanceId: clientInstanceIdRef.current,
      authStatus: authStatusRef.current,
      loginBannerReason: loginBannerReasonRef.current,
      hasSession: !!sessionStateRef.current,
      hasAuthSession: !!authSessionRef.current,
      hasProfile: !!profileRef.current,
      loading: loadingRef.current,
      profileLoading: profileLoadingRef.current,
      sessionUserId: sessionStateRef.current?.user?.id ?? null,
      authSessionAuthId: authSessionRef.current?.auth_id ?? null,
      sessionRevokedReason: authSessionRef.current?.session_revoked_reason ?? null,
      sessionRef: sessionRef.current,
    });
  }

  function debugFlowSignedInStep(step: string, extra?: Record<string, unknown>) {
    console.log('[FLOW_SIGNED_IN_STEP]', {
      step,
      clientInstanceId: clientInstanceIdRef.current,
      sessionRef: sessionRef.current,
      authStatus: authStatusRef.current,
      hasSession: !!sessionStateRef.current,
      hasAuthSession: !!authSessionRef.current,
      hasProfile: !!profileRef.current,
      ...extra,
    });
  }

  function clearLocalState(options?: {
    preserveBanner?: boolean;
    bannerReason?: SessionRevokedReason | null;
  }) {
    const preserveBanner = options?.preserveBanner ?? false;
    const bannerReason = options?.bannerReason ?? null;

    sessionRef.current = null;
    setSession(null);
    setProfile(null);
    setAuthSession(null);
    setAuthStatus('unauthenticated');
    setLoading(false);
    setProfileLoading(false);

    if (preserveBanner) {
      setLoginBannerReason(bannerReason);
    } else {
      setLoginBannerReason(null);
    }
  }

  async function claimActiveClientSession(clientInstanceId: string) {
    const { data, error } = await supabase.rpc('rpc_auth_claim_active_client_session', {
      p_client_instance_id: clientInstanceId,
    });

    console.log('[RCC_CLAIM]', {
      clientInstanceId,
      error: error?.message ?? null,
      data: data ?? null,
    });

    if (error) throw error;
    return data;
  }

  async function resolveInstitutionalSessionState(clientInstanceId: string) {
    const { data, error } = await supabase.rpc('rpc_auth_resolve_session_state', {
      p_client_instance_id: clientInstanceId,
    });

    const row = Array.isArray(data) ? data[0] : null;

    console.log('[RCC_RESOLVE]', {
      clientInstanceId,
      error: error?.message ?? null,
      row: row ?? null,
    });

    if (error) throw error;
    return row;
  }

  async function forceInstitutionalLogout(reason: SessionRevokedReason) {
    console.log('[RCC_FORCE_LOGOUT]', {
      clientInstanceId: clientInstanceIdRef.current,
      reason,
    });

    clearLocalState({
      preserveBanner: true,
      bannerReason: reason,
    });

    const { error } = await supabase.auth.signOut();

    if (error) {
      console.log('[RCC_FORCE_LOGOUT_ERROR]', {
        message: error.message,
      });
    }

    await debugSessionSnapshot(`forceInstitutionalLogout_${reason}`);
    debugStateSnapshot(`forceInstitutionalLogout_${reason}_final_state`);
  }

  async function fetchInstitutionalAuth(clientInstanceId: string) {
    if (fetchingInstitutionalAuthRef.current) {
      console.log('[H1_FETCH_INSTITUTIONAL_AUTH] skipped_concurrent_call', { clientInstanceId });
      return;
    }
    fetchingInstitutionalAuthRef.current = true;

    try {
      let isV3 = false;

      try {
        const { data: configData, error: configError } = await supabase
          .from('v_auth_app_config')
          .select('auth_contract_version')
          .single();

        if (!configError && configData?.auth_contract_version) {
          isV3 = isAtLeastRcc03(configData.auth_contract_version);
        }

        console.log('[H1_RCC_VERSION]', {
          auth_contract_version: configData?.auth_contract_version ?? null,
          isV3,
          configError: configError?.message ?? null,
        });
      } catch (e) {
        console.warn('[AUTH] Falha ao ler auth_contract_version, fallback para RCC < 0.3');
        console.log('[H1_RCC_VERSION_EXCEPTION]', {
          message: (e as any)?.message ?? null,
        });
      }

      let data: any = null;
      let error: any = null;

      try {
        data = await resolveInstitutionalSessionState(clientInstanceId);
      } catch (rpcError: any) {
        error = rpcError;
      }

      console.log('[H1_V_AUTH_SESSION]', {
        clientInstanceId,
        hasData: !!data,
        error: error?.message ?? null,
        row: data ?? null,
      });

      if (error || !data) {
        const hasActiveSession = sessionStateRef.current !== null;
        const hasActiveProfile = profileRef.current !== null;

        console.log('[GOOGLE_POST_AUTH] hasSupabaseSession', {
          hasActiveSession,
          clientInstanceId,
        });
        console.log('[GOOGLE_POST_AUTH] userId', {
          present: sessionStateRef.current?.user?.id != null,
          clientInstanceId,
        });

        if (hasActiveSession) {
          // Sessão Supabase válida mas sem row em auth_client_sessions (ou RPC retornou null):
          // Novo recruta pré-onboarding — ex: usuário Google recém-criado, sem recruta institucional.
          // Frontend NÃO inventa perfil: apenas reconhece o estado para permitir onboarding.
          if (!hasActiveProfile) {
            console.log('[GOOGLE_POST_AUTH] profileMissingPGRST116', { clientInstanceId });
          }
          console.log('[GOOGLE_POST_AUTH] treatingAsNewRecruta', { clientInstanceId });
          setAuthSession(null);
          setLoginBannerReason(null);
          setAuthStatus('authenticated');
        } else {
          setAuthSession(null);
          setLoginBannerReason(null);
          setAuthStatus('unauthenticated');

          console.log('[H1_V_AUTH_SESSION_RESULT]', {
            result: 'unauthenticated_due_to_missing_or_error',
            clientInstanceId,
          });
        }

        return;
      }

      setAuthSession(data);

      const rawReason = data.session_revoked_reason;
      let reason: SessionRevokedReason = 'none';

      if (
        rawReason === 'security_logout' ||
        rawReason === 'session_expired' ||
        rawReason === 'user_action' ||
        rawReason === 'none'
      ) {
        reason = rawReason as SessionRevokedReason;
      }

      if (isV3 && (reason === 'security_logout' || reason === 'session_expired')) {
        console.log('[H1_BANNER_DECISION]', {
          clientInstanceId,
          isV3,
          rawReason,
          normalizedReason: reason,
          willShowBanner: true,
        });

        await forceInstitutionalLogout(reason);
        return;
      }

      if (isV3) {
        setLoginBannerReason(null);

        console.log('[H1_BANNER_DECISION]', {
          clientInstanceId,
          isV3,
          rawReason,
          normalizedReason: reason,
          willShowBanner: false,
        });
      } else {
        setLoginBannerReason(null);

        console.log('[H1_BANNER_DECISION]', {
          clientInstanceId,
          isV3,
          rawReason: null,
          normalizedReason: null,
          willShowBanner: false,
        });
      }

      if (data.inactive_user) {
        setAuthStatus('inactive_user');
        console.log('[H1_AUTH_STATUS_DECISION]', { clientInstanceId, nextAuthStatus: 'inactive_user' });
        return;
      }

      if (data.account_locked) {
        setAuthStatus('account_locked');
        console.log('[H1_AUTH_STATUS_DECISION]', { clientInstanceId, nextAuthStatus: 'account_locked' });
        return;
      }

      if (data.password_expired) {
        setAuthStatus('password_expired');
        console.log('[H1_AUTH_STATUS_DECISION]', { clientInstanceId, nextAuthStatus: 'password_expired' });
        return;
      }

      if (data.requires_mfa) {
        setAuthStatus('requires_mfa');
        console.log('[H1_AUTH_STATUS_DECISION]', { clientInstanceId, nextAuthStatus: 'requires_mfa' });
        return;
      }

      // Garante que a nova sessão não herde estado visual prévio
      setLoginBannerReason(null);
      setAuthStatus('authenticated');
      console.log('[H1_AUTH_STATUS_DECISION]', { clientInstanceId, nextAuthStatus: 'authenticated' });
    } finally {
      fetchingInstitutionalAuthRef.current = false;
    }
  }

  useEffect(() => {
    if (authStatus !== 'unauthenticated') {
      setLoginBannerReason(null);
    }
  }, [authStatus]);

  async function loadProfile(userId: string) {
    try {
      if (sessionRef.current !== userId) return;

      setProfileLoading(true);

      const { data, error } = await supabase
        .from('v_identidade_recruta')
        .select('*')
        .eq('auth_id', userId)
        .single();

      if (sessionRef.current !== userId) return;

      if (error) {
        // PGRST116 = "0 rows returned" via .single()
        // Recruta autenticado mas sem row em v_identidade_recruta = usuário novo, pré-onboarding.
        // Não é erro institucional — profile fica null, BootstrapGate encaminha para onboarding.
        const isPgrst116 = (error as any).code === 'PGRST116';
        if (isPgrst116) {
          console.log('[H1_PROFILE_LOAD]', {
            userId,
            error: 'PGRST116_no_recruta_row',
            hasProfile: false,
            note: 'novo_recruta_pre_onboarding',
          });
        } else {
          console.error('[AUTH] Error loading profile from v_identidade_recruta:', error);
          console.log('[H1_PROFILE_LOAD]', {
            userId,
            error: error.message,
            hasProfile: false,
          });
        }
      } else {
        setProfile(data as Profile);
        console.log('[H1_PROFILE_LOAD]', {
          userId,
          error: null,
          hasProfile: true,
          recruta_id: (data as any)?.id ?? null,
        });
      }
    } catch (e: any) {
      console.error('[AUTH] Exception loading profile:', e);
      console.log('[H1_PROFILE_LOAD_EXCEPTION]', {
        userId,
        message: e?.message ?? null,
      });
    } finally {
      if (sessionRef.current === userId) {
        setProfileLoading(false);
      }
    }
  }

  async function handleAuthStateChange(
    event: string,
    currentSession: Session | null,
    mounted: boolean
  ) {
    if (!mounted) return;

    const activeClientInstanceId =
      clientInstanceIdRef.current ?? (await getOrCreateClientInstanceId());

    clientInstanceIdRef.current = activeClientInstanceId;

    console.log('[H1_AUTH_STATE_CHANGE]', {
      event,
      hasCurrentSession: !!currentSession,
      currentUserId: currentSession?.user?.id ?? null,
      currentEmail: currentSession?.user?.email ?? null,
      clientInstanceId: activeClientInstanceId,
    });

    // INITIAL_SESSION é disparado quando a subscription é registrada.
    // initialize() já processou o estado inicial da sessão — evitar processamento duplo.
    if (event === 'INITIAL_SESSION') {
      console.log('[H1_AUTH_STATE_CHANGE] skipped_initial_session_already_handled_by_initialize');
      return;
    }

    if (currentSession) {
      setSession(currentSession);

      debugFlowSignedInStep('entered_currentSession_branch', {
        event,
        currentUserId: currentSession.user.id,
      });

      if (sessionRef.current !== currentSession.user.id) {
        debugFlowSignedInStep('before_set_sessionRef_for_new_user', {
          previousSessionRef: sessionRef.current,
          nextSessionRef: currentSession.user.id,
        });

        sessionRef.current = currentSession.user.id;
        setProfile(null);
        setLoading(true);

        try {
          debugFlowSignedInStep('before_loadProfile', {
            event,
            currentUserId: currentSession.user.id,
          });

          await loadProfile(currentSession.user.id);

          debugFlowSignedInStep('after_loadProfile', {
            event,
            currentUserId: currentSession.user.id,
          });
        } catch (err: any) {
          console.log('[FLOW_SIGNED_IN_STEP]', {
            step: 'loadProfile_error',
            clientInstanceId: activeClientInstanceId,
            message: err?.message ?? null,
          });
        } finally {
          setLoading(false);
        }
      } else {
        debugFlowSignedInStep('skip_loadProfile_same_user', {
          event,
          currentUserId: currentSession.user.id,
        });
      }

      try {
        if (event === 'SIGNED_IN') {
          debugFlowSignedInStep('before_claim', {
            event,
            currentUserId: currentSession.user.id,
          });

          await claimActiveClientSession(activeClientInstanceId);

          debugFlowSignedInStep('after_claim', {
            event,
            currentUserId: currentSession.user.id,
          });
        } else {
          debugFlowSignedInStep('skip_claim_non_signed_in_event', {
            event,
            currentUserId: currentSession.user.id,
          });
        }

        debugFlowSignedInStep('before_fetchInstitutionalAuth', {
          event,
          currentUserId: currentSession.user.id,
        });

        await fetchInstitutionalAuth(activeClientInstanceId);

        debugFlowSignedInStep('after_fetchInstitutionalAuth', {
          event,
          currentUserId: currentSession.user.id,
        });

        await debugSessionSnapshot(`onAuthStateChange_${event}_with_session`);

        debugFlowSignedInStep('after_debugSessionSnapshot', {
          event,
          currentUserId: currentSession.user.id,
        });
      } catch (err: any) {
        console.log('[FLOW_SIGNED_IN_STEP]', {
          step: 'post_signin_pipeline_error',
          clientInstanceId: activeClientInstanceId,
          event,
          message: err?.message ?? null,
        });
      }
    } else {
      clearLocalState({
        preserveBanner: true,
        bannerReason: loginBannerReasonRef.current,
      });

      console.log('[H1_AUTH_STATE_CHANGE_RESULT]', {
        event,
        result: 'unauthenticated_no_current_session',
        clientInstanceId: activeClientInstanceId,
      });

      await debugSessionSnapshot(`onAuthStateChange_${event}_without_session`);
    }
  }

  useEffect(() => {
    let mounted = true;
    let unsubscribe: (() => void) | null = null;

    async function initialize() {
      try {
        const clientInstanceId = await getOrCreateClientInstanceId();
        clientInstanceIdRef.current = clientInstanceId;

        console.log('[CLIENT_INSTANCE_ID]', {
          clientInstanceId,
        });

        const {
          data: { session: initialSession },
        } = await supabase.auth.getSession();

        console.log('[H1_INIT_SESSION]', {
          hasInitialSession: !!initialSession,
          userId: initialSession?.user?.id ?? null,
          email: initialSession?.user?.email ?? null,
          clientInstanceId,
        });

        if (!initialSession) {
          if (mounted) {
            clearLocalState();
            debugStateSnapshot('initialize_no_session');
          }
        } else {
          if (mounted) {
            sessionRef.current = initialSession.user.id;
            setSession(initialSession);

            try {
              await loadProfile(initialSession.user.id);
            } catch (err: any) {
              console.log('[FLOW_SIGNED_IN_STEP]', {
                step: 'initialize_loadProfile_error',
                clientInstanceId,
                message: err?.message ?? null,
              });
            }

            await fetchInstitutionalAuth(clientInstanceId);

            setLoading(false);

            await debugSessionSnapshot('initialize_with_session');
          }
        }

        const { data } = supabase.auth.onAuthStateChange((event, currentSession) => {
          void handleAuthStateChange(event, currentSession, mounted);
        });

        startSessionGuardian();

        unsubscribe = () => {
          data.subscription.unsubscribe();
        };
      } catch (err: any) {
        console.error('[AUTH] Init failed:', err);
        console.log('[H1_INIT_EXCEPTION]', {
          message: err?.message ?? null,
        });
        if (mounted) setLoading(false);
      }
    }

    initialize();

    return () => {
      mounted = false;
      if (unsubscribe) unsubscribe();
    };
  }, []);

  useEffect(() => {
    const sub = AppState.addEventListener('change', async (state: AppStateStatus) => {
      if (state === 'active') {
        const clientInstanceId =
          clientInstanceIdRef.current ?? (await getOrCreateClientInstanceId());

        clientInstanceIdRef.current = clientInstanceId;

        console.log('[H1_APPSTATE]', {
          state: 'active',
          clientInstanceId,
        });

        await debugSessionSnapshot('app_became_active_before_revalidation');
        await fetchInstitutionalAuth(clientInstanceId);
        await debugSessionSnapshot('app_became_active_after_revalidation');
        debugStateSnapshot('app_became_active_final_state');
      }
    });

    return () => sub.remove();
  }, []);

  const signIn = async (email: string, password: string) => {
    // CORREÇÃO 1 — LIMPAR BANNER NO INÍCIO DO LOGIN
    // Impede persistência visual indesejada na tentativa de nova sessão
    setLoginBannerReason(null);

    const clientInstanceId =
      clientInstanceIdRef.current ?? (await getOrCreateClientInstanceId());

    clientInstanceIdRef.current = clientInstanceId;

    console.log('[H1_SIGN_IN_ATTEMPT]', {
      email,
      clientInstanceId,
    });

    const { error } = await supabase.auth.signInWithPassword({ email, password });

    if (error) {
      console.log('[H1_SIGN_IN_ERROR]', {
        clientInstanceId,
        message: error.message,
      });
      throw error;
    }

    console.log('[H1_SIGN_IN_SUCCESS]', {
      email,
      clientInstanceId,
    });
  };

  const signOut = async () => {
    console.log('[H1_SIGN_OUT_START]', {
      clientInstanceId: clientInstanceIdRef.current,
      authStatus: authStatusRef.current,
      loginBannerReason: loginBannerReasonRef.current,
      hasSession: !!sessionStateRef.current,
      hasAuthSession: !!authSessionRef.current,
    });

    setLoginBannerReason(null);
    clearLocalState();

    const { error } = await supabase.auth.signOut();

    if (error) {
      console.log('[H1_SIGN_OUT_ERROR]', {
        message: error.message,
      });
      throw error;
    }

    await debugSessionSnapshot('signOut_after_supabase_signOut');
    debugStateSnapshot('signOut_final_state');
  };

  const refetchProfile = async () => {
    if (sessionStateRef.current?.user) {
      console.log('[H1_REFETCH_PROFILE]', {
        userId: sessionStateRef.current.user.id,
        clientInstanceId: clientInstanceIdRef.current,
      });

      await loadProfile(sessionStateRef.current.user.id);
    }
  };

  const value: AuthContextType = {
    loginBannerReason,
    authStatus,
    authSession,
    session,
    user: session?.user ?? null,
    profile,
    loading,
    profileLoading,
    signIn,
    signOut,
    refetchProfile,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth deve ser usado dentro de um AuthProvider');
  }
  return context;
}
