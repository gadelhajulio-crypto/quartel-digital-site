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
    ScrollView,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { colors } from '../../src/theme';
import { supabase } from '../../src/lib/supabase';

export default function SignupScreen() {
    const router = useRouter();

    const [name, setName] = useState('');
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [showPassword, setShowPassword] = useState(false);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState('');

    const handleSignup = async () => {
        setError('');

        if (!name.trim()) {
            setError('O nome é obrigatório.');
            return;
        }
        if (!email.trim() || !email.includes('@')) {
            setError('Insira um e-mail válido.');
            return;
        }
        if (password.length < 6) {
            setError('A senha deve ter pelo menos 6 caracteres.');
            return;
        }

        setLoading(true);

        try {
            const { data, error } = await supabase.auth.signUp({
                email,
                password,
                options: {
                    data: {
                        nome: name.trim(),
                        // Não pedimos força nem nome de guerra aqui (onboarding fará isso)
                    },
                },
            });

            if (error) {
                throw error;
            }

            // Se o email não precisar de confirmação, a sessão será criada
            // O AppState Listener ou o AuthChangeListener assumirão o fluxo
            // Se precisar de e-mail, alertamos:
            if (data?.user && !data.session) {
                Alert.alert(
                    'Conta Criada',
                    'Sua conta foi criada. Por favor, verifique seu e-mail para continuar.',
                    [{ text: 'OK', onPress: () => router.back() }]
                );
            } else {
                // Sessão criada. Devolvemos para ser absorvido pelo layout/root layout AuthContext
                console.log('[SIGNUP] Cadastro e login automáticos efetuados.');
            }
        } catch (err: any) {
            console.error('[SIGNUP] Erro:', err.message);
            setError(err.message || 'Erro ao criar a conta.');
            Alert.alert('Erro', err.message || 'Verifique os dados informados.');
        } finally {
            // Deixamos a liberação do loading se der erro ou necessitar fallback
            setLoading(false);
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
                        {/* HEADER (Voltar) */}
                        <View style={styles.header}>
                            <TouchableOpacity onPress={() => router.back()} style={styles.backButton}>
                                <Ionicons name="arrow-back" size={24} color={colors.textPrimary} />
                            </TouchableOpacity>
                        </View>

                        {/* CARD CADASTRO */}
                        <View style={styles.card}>
                            <Text style={styles.title}>Criar conta</Text>
                            <Text style={styles.subtitle}>
                                Inicie sua jornada no Quartel Digital.
                            </Text>

                            {/* INPUT NOME */}
                            <View style={styles.inputWrapper}>
                                <Ionicons name="person-outline" size={20} color={colors.placeholder} />
                                <TextInput
                                    placeholder="Nome completo"
                                    placeholderTextColor={colors.placeholder}
                                    style={styles.input}
                                    value={name}
                                    onChangeText={setName}
                                    autoCapitalize="words"
                                    autoComplete="name"
                                />
                            </View>

                            {/* INPUT EMAIL */}
                            <View style={styles.inputWrapper}>
                                <Ionicons name="mail-outline" size={20} color={colors.placeholder} />
                                <TextInput
                                    placeholder="Seu melhor email"
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

                            {/* ERRO */}
                            {error !== '' && <Text style={styles.error}>{error}</Text>}

                            {/* BOTÃO */}
                            <TouchableOpacity
                                style={[
                                    styles.button,
                                    loading && { backgroundColor: colors.disabled },
                                ]}
                                onPress={handleSignup}
                                disabled={loading}
                            >
                                {loading ? (
                                    <ActivityIndicator color={colors.background} />
                                ) : (
                                    <Text style={styles.buttonText}>CADASTRAR</Text>
                                )}
                            </TouchableOpacity>
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
        justifyContent: 'center',
        paddingVertical: 60,
    },
    header: {
        position: 'absolute',
        top: 50,
        left: 24,
        zIndex: 10,
    },
    backButton: {
        padding: 8,
        marginLeft: -8,
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
        marginBottom: 8,
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
        fontSize: 14,
        fontWeight: '700',
        letterSpacing: 1,
    },
});
