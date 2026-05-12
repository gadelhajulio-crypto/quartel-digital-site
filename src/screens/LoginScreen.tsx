import React, { useState } from 'react';
import {
  View,
  Text,
  TouchableOpacity,
  StyleSheet,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import * as Linking from 'expo-linking';
import * as WebBrowser from 'expo-web-browser';
import { useAuth } from '../context/AuthContext';
import { supabase } from '../lib/supabase';
import { ObsidianScreen } from '../design/layout/ObsidianScreen';
import { InstitutionalCard } from '../design/components/InstitutionalCard';
import { InstitutionalInput } from '../design/components/InstitutionalInput';
import { InstitutionalButton } from '../design/components/InstitutionalButton';
import { InstitutionalBadge } from '../design/components/InstitutionalBadge';
import { InstitutionalSection } from '../design/components/InstitutionalSection';
import { obsidiana } from '../design/themes/obsidiana';
import { typographyPresets } from '../design/tokens/typography';
import { spacing } from '../design/tokens/spacing';
import { radius } from '../design/tokens/radius';
import { errorToString } from '../utils/institutionalErrorMapper';

// Completa qualquer auth session pendente no WebBrowser
WebBrowser.maybeCompleteAuthSession();

export default function LoginScreen() {
  const router = useRouter();
  const { signIn, loginBannerReason } = useAuth();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [googleLoading, setGoogleLoading] = useState(false);
  const [error, setError] = useState('');

  const handleLogin = async () => {
    setError('');
    setLoading(true);

    try {
      await signIn(email, password);
    } catch (err: any) {
      setError(errorToString(err));
    } finally {
      setLoading(false);
    }
  };

  const handleGoogleLogin = async () => {
    setError('');
    setGoogleLoading(true);
    console.log('[GOOGLE_OAUTH] start');

    // Flag: quando true, o loading é gerenciado pelo listener ou AuthContext
    let delegatedToListener = false;

    // Timeout de segurança: garante que o loading sempre termina
    const safetyTimeout = setTimeout(() => {
      console.warn('[GOOGLE_OAUTH] timeout_60s — resetando loading');
      setGoogleLoading(false);
      setError('Tempo de autenticação expirado. Tente novamente.');
    }, 60_000);

    try {
      // Detectar Expo Go (scheme customizado não funciona)
      const probeUrl = Linking.createURL('/');
      if (probeUrl.startsWith('exp://')) {
        console.warn('[GOOGLE_OAUTH] expo_go_detected');
        setError('Autenticação Google requer o aplicativo instalado nativamente. Acesse via build de produção ou desenvolvimento.');
        return;
      }

      const redirectTo = 'quarteldigital:///';
      console.log('[GOOGLE_OAUTH] redirectTo:', redirectTo);

      const { data, error: oauthError } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: {
          redirectTo,
          skipBrowserRedirect: true,
        },
      });

      if (oauthError || !data?.url) {
        console.warn('[GOOGLE_OAUTH] oauth_url_error:', oauthError?.message ?? 'url_missing');
        setError('Falha ao iniciar autenticação Google. Tente novamente.');
        return;
      }

      console.log('[GOOGLE_OAUTH] oauth_url: ok');

      // ── Ambas as plataformas: openAuthSessionAsync monitora o redirectUrl internamente
      console.log('[GOOGLE_OAUTH] flow: openAuthSessionAsync');
      const result = await WebBrowser.openAuthSessionAsync(data.url, redirectTo);
      console.log('[GOOGLE_OAUTH] browser_result:', result.type);

      if (result.type === 'cancel' || result.type === 'dismiss') {
        // Usuário cancelou voluntariamente — sem erro visível
        return;
      }

      if (result.type !== 'success') {
        console.warn('[GOOGLE_OAUTH] no_success_result:', result.type);
        setError('Autenticação não concluída. Verifique a conexão e tente novamente.');
        return;
      }

      const returnUrl: string = (result as any).url ?? '';

      // Parsear URL de forma segura (sem logar valores)
      let queryParams: URLSearchParams | null = null;
      let hashParams: URLSearchParams | null = null;
      try {
        const parsed = new URL(returnUrl);
        queryParams = parsed.searchParams;
        hashParams = new URLSearchParams(parsed.hash.replace(/^#/, ''));
      } catch {
        // URL malformada — tratar abaixo
      }

      const queryKeys = queryParams ? Array.from(queryParams.keys()) : [];
      const hashKeys = hashParams ? Array.from(hashParams.keys()) : [];

      console.log('[GOOGLE_OAUTH] callback_shape', {
        hasUrl: !!returnUrl,
        startsWithQuartelDigital: returnUrl.startsWith('quarteldigital'),
        hasQuery: queryKeys.length > 0,
        hasHash: hashKeys.length > 0,
        queryKeys,
        hashKeys,
      });

      // 1. Fluxo PKCE: code na query string
      const codeFromQuery = queryParams?.get('code') ?? null;
      // 2. Fluxo implícito: code no hash
      const codeFromHash = hashParams?.get('code') ?? null;
      const code = codeFromQuery ?? codeFromHash;

      if (code) {
        console.log('[GOOGLE_OAUTH] code_found: true');
        const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(returnUrl);
        if (exchangeError) {
          console.warn('[GOOGLE_OAUTH] exchange_error:', exchangeError.message);
          setError('Não foi possível concluir o acesso com Google.');
          return;
        }
        console.log('[GOOGLE_OAUTH] exchange_success');
        console.log('[GOOGLE_OAUTH] finalizing — AuthContext assume o controle');
        // Loading permanece true; AuthContext.onAuthStateChange redireciona e desmonta a tela
        return;
      }

      console.log('[GOOGLE_OAUTH] code_found: false');

      // 3. Fluxo implícito: tokens no hash
      const accessToken = hashParams?.get('access_token') ?? null;
      const refreshToken = hashParams?.get('refresh_token') ?? null;

      if (accessToken && refreshToken) {
        console.log('[GOOGLE_OAUTH] token_hash_found: true');
        const { error: sessionError } = await supabase.auth.setSession({
          access_token: accessToken,
          refresh_token: refreshToken,
        });
        if (sessionError) {
          console.warn('[GOOGLE_OAUTH] set_session_error:', sessionError.message);
          setError('Não foi possível concluir o acesso com Google.');
          return;
        }
        console.log('[GOOGLE_OAUTH] set_session_success');
        console.log('[GOOGLE_OAUTH] finalizing — AuthContext assume o controle');
        // Loading permanece true; AuthContext.onAuthStateChange redireciona e desmonta a tela
        return;
      }

      // 4. OAuth retornou erro explícito
      const oauthCallbackError = queryParams?.get('error') ?? hashParams?.get('error') ?? null;
      if (oauthCallbackError) {
        console.warn('[GOOGLE_OAUTH] oauth_error_found:', oauthCallbackError);
        setError('Não foi possível concluir o acesso com Google.');
        return;
      }

      // Nenhum dado reconhecível — callback inesperado
      console.warn('[GOOGLE_OAUTH] unrecognized_callback_shape', { queryKeys, hashKeys });
      setError('Não foi possível concluir o acesso com Google.');

    } catch (err) {
      console.warn('[GOOGLE_OAUTH] exception:', err);
      setError(errorToString(err));
    } finally {
      // Só limpa loading se o controle NÃO foi delegado ao listener Android
      if (!delegatedToListener) {
        clearTimeout(safetyTimeout);
        setGoogleLoading(false);
      }
    }
  };

  return (
    <ObsidianScreen scrollable avoidKeyboard>
      {/* LOGO */}
      <View style={styles.header}>
        <Ionicons name="shield-checkmark" size={64} color={obsidiana.colors.accent} />
        <Text style={[typographyPresets.displayTitle, { color: obsidiana.colors.accent, marginTop: 12 }]}>
          Quartel Digital
        </Text>
        <Text style={[typographyPresets.label, { color: obsidiana.colors.textSecondary, marginTop: 4 }]}>
          Sistema institucional · BR
        </Text>
      </View>

      {/* BANNER: sessão encerrada por segurança */}
      {loginBannerReason === 'security_logout' && (
        <View
          style={[
            styles.banner,
            {
              backgroundColor: obsidiana.colors.error + '20',
              borderColor: obsidiana.colors.error,
            },
          ]}
        >
          <Ionicons name="warning-outline" size={20} color={obsidiana.colors.error} />
          <Text style={[styles.bannerText, { color: obsidiana.colors.error }]}>
            Sessão encerrada por acesso em outro dispositivo. Faça login novamente.
          </Text>
        </View>
      )}

      {/* BANNER: sessão expirada */}
      {loginBannerReason === 'session_expired' && (
        <View
          style={[
            styles.banner,
            {
              backgroundColor: obsidiana.colors.warning + '20',
              borderColor: obsidiana.colors.warning,
            },
          ]}
        >
          <Ionicons name="time-outline" size={20} color={obsidiana.colors.warning} />
          <Text style={[styles.bannerText, { color: obsidiana.colors.warning }]}>
            Sessão expirada. Confirme sua identidade para continuar.
          </Text>
        </View>
      )}

      {/* CARD DE ACESSO */}
      <InstitutionalCard theme={obsidiana} elevated style={styles.card}>
        <InstitutionalSection
          title="Acesso institucional"
          theme={obsidiana}
          style={{ marginBottom: 0 }}
        >
          <InstitutionalInput
            theme={obsidiana}
            label="Identificação"
            placeholder="seu@email.com.br"
            value={email}
            onChangeText={setEmail}
            autoCapitalize="none"
            keyboardType="email-address"
            autoComplete="email"
            containerStyle={styles.inputSpacing}
          />

          <InstitutionalInput
            theme={obsidiana}
            label="Senha"
            placeholder="••••••••"
            value={password}
            onChangeText={setPassword}
            secureTextEntry={!showPassword}
            autoComplete="password"
            containerStyle={styles.inputSpacing}
            rightElement={
              <TouchableOpacity
                onPress={() => setShowPassword(!showPassword)}
                hitSlop={8}
              >
                <Ionicons
                  name={showPassword ? 'eye-outline' : 'eye-off-outline'}
                  size={20}
                  color={obsidiana.colors.muted}
                />
              </TouchableOpacity>
            }
          />

          <TouchableOpacity
            style={styles.forgotRow}
            onPress={() => router.push('/(auth)/forgot-password')}
          >
            <Text style={[typographyPresets.bodySmall, { color: obsidiana.colors.textSecondary }]}>
              Esqueci a senha
            </Text>
          </TouchableOpacity>

          {error !== '' && (
            <InstitutionalBadge
              theme={obsidiana}
              label={error}
              variant="error"
              style={styles.errorBadge}
            />
          )}

          <InstitutionalButton
            theme={obsidiana}
            label="Confirmar acesso"
            onPress={handleLogin}
            loading={loading}
            disabled={loading || googleLoading}
            size="l"
            style={styles.button}
          />

          {/* Divisor */}
          <View style={styles.dividerRow}>
            <View style={[styles.dividerLine, { backgroundColor: obsidiana.colors.border }]} />
            <Text style={[typographyPresets.label, { color: obsidiana.colors.muted }]}>ou</Text>
            <View style={[styles.dividerLine, { backgroundColor: obsidiana.colors.border }]} />
          </View>

          {/* Google OAuth */}
          <TouchableOpacity
            style={[
              styles.googleBtn,
              {
                backgroundColor: obsidiana.colors.card,
                borderColor: obsidiana.colors.border,
                opacity: loading || googleLoading ? 0.6 : 1,
              },
            ]}
            onPress={handleGoogleLogin}
            disabled={loading || googleLoading}
            activeOpacity={0.8}
          >
            {googleLoading ? (
              <Ionicons name="refresh-outline" size={20} color={obsidiana.colors.muted} />
            ) : (
              <Ionicons name="logo-google" size={20} color={obsidiana.colors.textSecondary} />
            )}
            <Text style={[typographyPresets.body, { color: obsidiana.colors.textSecondary, marginLeft: spacing.s }]}>
              {googleLoading ? 'Aguardando autenticação...' : 'Acessar com conta Google'}
            </Text>
          </TouchableOpacity>
        </InstitutionalSection>
      </InstitutionalCard>

      {/* RODAPÉ */}
      <View style={styles.footer}>
        <View style={[styles.dividerLine, { backgroundColor: obsidiana.colors.border, width: '50%' }]} />
        <TouchableOpacity onPress={() => router.push('/(auth)/signup')}>
          <Text style={[typographyPresets.bodySmall, { color: obsidiana.colors.textSecondary }]}>
            Criar conta
          </Text>
        </TouchableOpacity>
        <Text style={[typographyPresets.label, { color: obsidiana.colors.muted, marginTop: 4 }]}>
          Uso restrito · Plataforma institucional
        </Text>
      </View>
    </ObsidianScreen>
  );
}

const styles = StyleSheet.create({
  header: {
    alignItems: 'center',
    marginTop: 24,
    marginBottom: 28,
  },
  banner: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 10,
    padding: 14,
    borderRadius: obsidiana.radius.s,
    borderWidth: 1,
    marginBottom: 16,
  },
  bannerText: {
    flex: 1,
    fontSize: 13,
    lineHeight: 19,
  },
  card: {
    maxWidth: 420,
    alignSelf: 'center',
    width: '100%',
  },
  inputSpacing: {
    marginBottom: 14,
  },
  forgotRow: {
    alignSelf: 'flex-end',
    marginBottom: 8,
  },
  errorBadge: {
    alignSelf: 'stretch',
    marginBottom: 12,
  },
  button: {
    marginTop: 8,
  },
  dividerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: spacing.s,
    marginVertical: spacing.m,
  },
  dividerLine: {
    flex: 1,
    height: 1,
  },
  googleBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 14,
    paddingHorizontal: spacing.m,
    borderRadius: radius.s,
    borderWidth: 1,
  },
  footer: {
    alignItems: 'center',
    gap: 10,
    marginTop: 32,
    marginBottom: 24,
  },
});
