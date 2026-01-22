import React from 'react';
import {
    View,
    Text,
    StyleSheet,
    SafeAreaView,
    TouchableOpacity,
    Image,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { colors } from '../theme';

type Props = {
    onLogin: () => void;
    onRegister: () => void;
};

export default function IntroScreen({ onLogin, onRegister }: Props) {
    return (
        <SafeAreaView style={styles.safe}>
            <View style={styles.container}>

                {/* HEADER */}
                <View style={styles.header}>
                    {/* Fallback Icon instead of image if not available */}
                    <Ionicons name="shield-checkmark" size={96} color={colors.gold} />
                    {/* <Image
            source={require('../../assets/logo.png')}
            style={styles.logo}
          /> */}
                </View>

                {/* CONTEÚDO */}
                <View style={styles.content}>
                    <Text style={styles.title}>
                        Disciplina, conhecimento e direção.
                    </Text>

                    <Text style={styles.subtitle}>
                        O Quartel Digital é um ambiente institucional de formação,
                        organização e preparação contínua.
                    </Text>

                    <View style={styles.benefits}>
                        <Benefit text="Conteúdo estruturado e progressivo" />
                        <Benefit text="Orientação clara para cada fase" />
                        <Benefit text="Ambiente sério e objetivo" />
                    </View>
                </View>

                {/* AÇÕES */}
                <View style={styles.actions}>
                    <TouchableOpacity style={styles.primaryButton} onPress={onLogin}>
                        <Text style={styles.primaryText}>ENTRAR</Text>
                    </TouchableOpacity>

                    <TouchableOpacity onPress={onRegister}>
                        <Text style={styles.secondaryText}>Criar conta</Text>
                    </TouchableOpacity>
                </View>

            </View>
        </SafeAreaView>
    );
}

function Benefit({ text }: { text: string }) {
    return (
        <View style={styles.benefitItem}>
            <Ionicons
                name="checkmark-circle-outline"
                size={20}
                color={colors.gold}
            />
            <Text style={styles.benefitText}>{text}</Text>
        </View>
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
        marginTop: 48,
    },
    logo: {
        width: 96,
        height: 96,
        resizeMode: 'contain',
    },
    content: {
        alignItems: 'center',
        gap: 16,
    },
    title: {
        color: colors.textPrimary,
        fontSize: 26,
        fontWeight: '700',
        textAlign: 'center',
        lineHeight: 34,
    },
    subtitle: {
        color: colors.textSecondary,
        fontSize: 15,
        textAlign: 'center',
        lineHeight: 22,
    },
    benefits: {
        marginTop: 16,
        gap: 12,
        width: '100%',
    },
    benefitItem: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 8,
    },
    benefitText: {
        color: colors.textSecondary,
        fontSize: 14,
        fontWeight: '500',
    },
    actions: {
        gap: 16,
        marginBottom: 24,
    },
    primaryButton: {
        height: 52,
        borderRadius: 10,
        backgroundColor: colors.gold,
        alignItems: 'center',
        justifyContent: 'center',
    },
    primaryText: {
        color: colors.background,
        fontSize: 16,
        fontWeight: '600',
        letterSpacing: 1,
    },
    secondaryText: {
        color: colors.textSecondary,
        fontSize: 14,
        textAlign: 'center',
    },
});
