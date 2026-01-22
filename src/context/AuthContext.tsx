import React, { createContext, useContext, useEffect, useState, useRef } from 'react';
import { Session, User } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';

// 🔐 TIPOS
interface AuthContextType {
  session: Session | null;
  user: User | null;
  profile: Profile | null;
  loading: boolean;
  signIn: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  refetchProfile: () => Promise<void>;
}

export type Profile = {
  id: string;
  nome: string;
  patente: string;
  forca: 'marinha' | 'exercito' | 'aeronautica';
  nivel_atual: number;
  xp: number;
  avatar_url?: string;
  instructor_profile_id?: 'objetivo' | 'estrategico' | 'didatico' | null;
  tipo_acesso: 'degustacao' | 'completo';
  ativo: boolean;
};

// 🏗️ CRIAÇÃO DO CONTEXTO
const AuthContext = createContext<AuthContextType | undefined>(undefined);

// 🎯 PROVIDER
export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [loading, setLoading] = useState(true);

  // Ref para garantir que o profile carregado corresponde à sessão atual (Race Condition Lock)
  const sessionRef = useRef<string | null>(null);

  // 🔄 CARREGAR PERFIL (Centralizado e Seguro)
  async function loadProfile(userId: string) {
    try {
      // 🔒 Verifica se o usuário ainda é o mesmo da solicitação
      if (sessionRef.current !== userId) return;

      console.log('[AUTH] Loading profile for:', userId);
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .single();

      // 🔒 Verifica novamente antes de setar estado
      if (sessionRef.current !== userId) return;

      if (error) {
        console.error('[AUTH] Error loading profile:', error);
        // Fallback or Error State? For now, we allow generic profile or null.
        // In production, we might want to retry or block. 
        // Keeping null signals "No Profile" -> Onboarding might trigger.
      } else {
        setProfile(data);
      }
    } catch (e) {
      console.error('[AUTH] Exception loading profile:', e);
    }
  }

  // 🔄 INICIALIZAÇÃO E LISTENER (Unified Flow)
  useEffect(() => {
    let mounted = true;

    async function initialize() {
      try {
        // 1. Boot: Obter sessão inicial
        const { data: { session: initialSession } } = await supabase.auth.getSession();

        if (mounted) {
          if (initialSession) {
            sessionRef.current = initialSession.user.id;
            setSession(initialSession);
            await loadProfile(initialSession.user.id);
          }
          setLoading(false);
        }

        // 2. Listener: Única fonte de verdade para atualizações
        const { data: { subscription } } = supabase.auth.onAuthStateChange(async (event, currentSession) => {
          console.log(`[AUTH] Event: ${event}`);

          if (!mounted) return;

          if (currentSession) {
            setSession(currentSession);

            // Se o usuário mudou (ou é novo login), carrega perfil
            if (sessionRef.current !== currentSession.user.id) {
              sessionRef.current = currentSession.user.id;
              setProfile(null); // Limpa perfil anterior para evitar vazamento
              setLoading(true); // Opcional: mostrar loading durante troca de perfil
              await loadProfile(currentSession.user.id);
              setLoading(false);
            }
          } else {
            // Logout Clean
            console.log('[AUTH] Cleaning session state');
            sessionRef.current = null;
            setSession(null);
            setProfile(null);
            setLoading(false);
          }
        });

        return () => {
          subscription.unsubscribe();
        };

      } catch (err) {
        console.error('[AUTH] Init failed:', err);
        if (mounted) setLoading(false);
      }
    }

    initialize();

    return () => {
      mounted = false;
    };
  }, []);

  // 🔑 FUNÇÃO DE LOGIN (State-less, deixa o listener agir)
  const signIn = async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) throw error;
  };

  // 🚪 FUNÇÃO DE LOGOUT (Clean State Immediately)
  const signOut = async () => {
    // 1. Limpa estado local IMEDIATAMENTE e desvincula a referência
    // Isso garante que a UI reaja instantaneamente antes do Supabase processar
    sessionRef.current = null;
    setSession(null);
    setProfile(null);
    setLoading(false); // Garante que loading pare se estiver rodando

    // 2. Chama Supabase para limpar no backend/storage
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
  };

  const refetchProfile = async () => {
    if (session?.user) await loadProfile(session.user.id);
  };


  // NOTE:
  // signUp is intentionally NOT exposed here.
  // User creation is handled by a controlled onboarding / backend flow
  // to preserve institutional governance and avoid uncontrolled account creation.


  const value: AuthContextType = {
    session,
    user: session?.user ?? null,
    profile,
    loading,
    signIn,
    signOut,
    refetchProfile
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

// 🪝 HOOK
export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth deve ser usado dentro de um AuthProvider');
  }
  return context;
}