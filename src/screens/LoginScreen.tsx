import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  SafeAreaView,
  KeyboardAvoidingView,
  Platform,
  ActivityIndicator,
  Alert,
  Image,
  ScrollView,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { colors } from '../theme';
import { useAuth } from '../context/AuthContext'; // ⭐ MUDANÇA CRÍTICA

export default function LoginScreen() {
  const router = useRouter();
  const { signIn } = useAuth(); // ⭐ USA O MÉTODO DO CONTEXT
  
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleLogin = async () => {
    setError('');
    setLoading(true);

    try {
      // ⭐ USA O signIn DO CONTEXT (não do authService)
      await signIn(email, password);
      console.log('[LOGIN] ✅ Login bem-sucedido! Aguardando redirecionamento automático...');
      // O AuthContext + _layout.tsx vão cuidar do redirecionamento
      
    } catch (err: any) {
      console.error('[LOGIN] ❌ Erro:', err.message);
      setError(err.message || 'Erro ao entrar.');
      Alert.alert('Erro no Login', err.message || 'Verifique suas credenciais.');
      setLoading(false); // Só para de carregar em caso de erro
    }
  };

  return (
    <SafeAreaView style={styles.safe}>
      <KeyboardAvoidingView
        style={{ flex: 1 }}
        behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
      >
        <ScrollView
          contentContainerStyle={{ flexGrow: 1, justifyContent: 'center' }}
          showsVerticalScrollIndicator={false}
          keyboardShouldPersistTaps="handled"
        >
          <View style={styles.container}>
            {/* HEADER */}
            <View style={styles.header}>
              <Image
                source={require('../../assets/logorecrutapadrao.png')}
                style={styles.logo}
              />
            </View>

            {/* CARD LOGIN */}
            <View style={styles.card}>
              <Text style={styles.title}>Acesso Restrito</Text>
              <Text style={styles.subtitle}>
                Identifique-se para acessar o sistema
              </Text>

              {/* INPUT EMAIL */}
              <View style={styles.inputWrapper}>
                <Ionicons name="mail-outline" size={20} color={colors.placeholder} />
                <TextInput
                  placeholder="Email ou usuário"
                  placeholderTextColor={colors.placeholder}
                  style={styles.input}
                  value={email}
                  onChangeText={setEmail}
                  autoCapitalize="none"
                  keyboardType="email-address"
                  autoComplete="email"
                />
              </View>

              {/* INPUT SENHA */}
              <View style={styles.inputWrapper}>
                <Ionicons
                  name="lock-closed-outline"
                  size={20}
                  color={colors.placeholder}
                />
                <TextInput
                  placeholder="Senha"
                  placeholderTextColor={colors.placeholder}
                  style={styles.input}
                  value={password}
                  onChangeText={setPassword}
                  secureTextEntry={!showPassword}
                  autoComplete="password"
                />
                <TouchableOpacity onPress={() => setShowPassword(!showPassword)}>
                  <Ionicons
                    name={showPassword ? "eye-outline" : "eye-off-outline"}
                    size={20}
                    color={colors.placeholder}
                  />
                </TouchableOpacity>
              </View>

              {/* LINK SENHA */}
              <TouchableOpacity
                style={styles.forgot}
                onPress={() => {
                  Alert.alert('Funcionalidade em Breve', 'A recuperação de senha será implementada na próxima etapa.');
                }}
              >
                <Text style={styles.forgotText}>Esqueci minha senha</Text>
              </TouchableOpacity>

              {/* ERRO */}
              {error !== '' && <Text style={styles.error}>{error}</Text>}

              {/* BOTÃO */}
              <TouchableOpacity
                style={[
                  styles.button,
                  loading && { backgroundColor: colors.disabled },
                ]}
                onPress={handleLogin}
                disabled={loading}
              >
                {loading ? (
                  <ActivityIndicator color={colors.background} />
                ) : (
                  <Text style={styles.buttonText}>ENTRAR</Text>
                )}
              </TouchableOpacity>
            </View>

            {/* RODAPÉ */}
            <View style={styles.footer}>
              <View style={styles.divider} />
              <TouchableOpacity onPress={() => {
                Alert.alert('Funcionalidade em Breve', 'O registro será liberado em breve.');
              }}>
                <Text style={styles.createAccount}>Criar conta</Text>
              </TouchableOpacity>
              <Text style={styles.legal}>
                Uso restrito • Plataforma institucional
              </Text>
            </View>
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: colors.background,
  },
  container: {
    flex: 1,
    paddingHorizontal: 24,
    justifyContent: 'space-between',
  },
  header: {
    alignItems: 'center',
    marginTop: 32,
  },
  logo: {
    width: 240,
    height: 240,
    resizeMode: 'contain',
    marginBottom: 12,
  },
  card: {
    backgroundColor: colors.card,
    borderRadius: 16,
    padding: 24,
    gap: 16,
    maxWidth: 420,
    alignSelf: 'center',
    width: '100%',
    elevation: 6,
  },
  title: {
    fontSize: 22,
    color: colors.textPrimary,
    fontWeight: '600',
  },
  subtitle: {
    fontSize: 14,
    color: colors.textSecondary,
    lineHeight: 20,
  },
  inputWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: colors.background,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: colors.border,
    paddingHorizontal: 12,
    height: 52,
    gap: 8,
  },
  input: {
    flex: 1,
    color: colors.textPrimary,
    fontSize: 14,
  },
  forgot: {
    alignSelf: 'flex-end',
  },
  forgotText: {
    fontSize: 13,
    color: colors.textSecondary,
  },
  error: {
    color: colors.error,
    fontSize: 13,
    textAlign: 'center',
  },
  button: {
    height: 52,
    borderRadius: 10,
    backgroundColor: colors.gold,
    alignItems: 'center',
    justifyContent: 'center',
    marginTop: 8,
  },
  buttonText: {
    color: colors.background,
    fontSize: 16,
    fontWeight: '600',
    letterSpacing: 1,
  },
  footer: {
    alignItems: 'center',
    gap: 12,
    marginBottom: 16,
  },
  divider: {
    height: 1,
    width: '60%',
    backgroundColor: colors.border,
  },
  createAccount: {
    color: colors.textSecondary,
    fontSize: 14,
  },
  legal: {
    fontSize: 12,
    color: colors.placeholder,
  },
});