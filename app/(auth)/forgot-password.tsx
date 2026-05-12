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
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import { colors } from '../../src/theme';
import { supabase } from '../../src/lib/supabase';

export default function ForgotPasswordScreen() {
    const router = useRouter();
    const [email, setEmail] = useState('');
    const [loading, setLoading] = useState(false);

    const handleReset = async () => {
        if (!email) {
            Alert.alert('E-mail necessário', 'Por favor, insira seu e-mail para continuar.');
            return;
        }

        setLoading(true);

        try {
            const { error } = await supabase.auth.resetPasswordForEmail(email, {
                redirectTo: 'quarteldigital://reset-password/',
            });

            if (error) throw error;

            Alert.alert(
                'E-mail Enviado',
                'Se o email estiver cadastrado, você receberá um link para redefinir sua senha.',
                [{ text: 'OK', onPress: () => router.back() }]
            );
        } catch (err: any) {
            console.error('[FORGOT PASSWORD] Erro:', err.message);
            Alert.alert('Erro', err.message || 'Ocorreu um erro ao tentar recuperar a senha.');
        } finally {
            setLoading(false);
        }
    };

    return (
        <SafeAreaView style={styles.safe}>
            <KeyboardAvoidingView
                style={{ flex: 1 }}
                behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
            >
                <View style={styles.container}>
                    {/* HEADER (Voltar) */}
                    <View style={styles.header}>
                        <TouchableOpacity onPress={() => router.back()} style={styles.backButton}>
                            <Ionicons name="arrow-back" size={24} color={colors.textPrimary} />
                        </TouchableOpacity>
                    </View>

                    {/* CARD */}
                    <View style={styles.card}>
                        <Text style={styles.title}>Recuperar acesso</Text>
                        <Text style={styles.subtitle}>
                            Informe seu email para receber o link de redefinição de senha.
                        </Text>

                        <View style={styles.inputWrapper}>
                            <Ionicons name="mail-outline" size={20} color={colors.placeholder} />
                            <TextInput
                                placeholder="Seu email"
                                placeholderTextColor={colors.placeholder}
                                style={styles.input}
                                value={email}
                                onChangeText={setEmail}
                                autoCapitalize="none"
                                keyboardType="email-address"
                                autoComplete="email"
                            />
                        </View>

                        <TouchableOpacity
                            style={[styles.button, loading && { backgroundColor: colors.disabled }]}
                            onPress={handleReset}
                            disabled={loading}
                        >
                            {loading ? (
                                <ActivityIndicator color={colors.background} />
                            ) : (
                                <Text style={styles.buttonText}>ENVIAR LINK DE RECUPERAÇÃO</Text>
                            )}
                        </TouchableOpacity>

                        <TouchableOpacity
                            style={styles.backToLoginButton}
                            onPress={() => router.back()}
                            disabled={loading}
                        >
                            <Text style={styles.backToLoginText}>Voltar ao login</Text>
                        </TouchableOpacity>
                    </View>
                </View>
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
    backToLoginButton: {
        alignItems: 'center',
        paddingVertical: 12,
    },
    backToLoginText: {
        color: colors.textSecondary,
        fontSize: 14,
        fontWeight: '500',
    },
});
