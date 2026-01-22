import { supabase } from '../lib/supabase';

/**
 * 🔐 Função de Login
 * CRITICAL: Esta função é chamada pela tela de login
 * Ela NÃO atualiza o contexto diretamente
 * O onAuthStateChange do AuthContext é que detecta a mudança
 */
export async function signIn(email: string, password: string) {
  console.log('[AUTH SERVICE] 🔑 Tentando login...');

  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  if (error) {
    console.error('[AUTH SERVICE] ❌ Erro:', error.message);
    throw error;
  }

  console.log('[AUTH SERVICE] ✅ Login bem-sucedido!', {
    userId: data.user?.id,
    hasSession: !!data.session
  });

  // ⭐ O onAuthStateChange do AuthContext será disparado automaticamente
  // e vai atualizar o estado global (session, user)
  return data;
}

/**
 * 🚪 Função de Logout
 */
export async function signOut() {
  console.log('[AUTH SERVICE] 🚪 Fazendo logout...');
  
  const { error } = await supabase.auth.signOut();
  
  if (error) {
    console.error('[AUTH SERVICE] ❌ Erro no logout:', error.message);
    throw error;
  }

  console.log('[AUTH SERVICE] ✅ Logout bem-sucedido');
}