import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Animated } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { useForceTheme } from '../../../src/context/ForceThemeContext';

export default function MissaoConcluidaScreen() {
    const router = useRouter();
    const params = useLocalSearchParams();
    const { xp = '50' } = params;
    const { theme } = useTheme();

    const fadeAnim = new Animated.Value(0);
    const scaleAnim = new Animated.Value(0.5);

    useEffect(() => {
        Animated.parallel([
            Animated.timing(fadeAnim, {
                toValue: 1,
                duration: 800,
                useNativeDriver: true,
            }),
            Animated.spring(scaleAnim, {
                toValue: 1,
                friction: 4,
                tension: 40,
                useNativeDriver: true,
            })
        ]).start();
    }, []);

    return (
        <SafeAreaView style={[styles.container, { backgroundColor: theme.background }]}>
            <View style={styles.content}>

                <Animated.Text style={[styles.title, { opacity: fadeAnim, color: theme.secondary }]}>
                    MISSÃO CUMPRIDA
                </Animated.Text>

                {/* Large Shield */}
                <Animated.View style={[
                    styles.shieldContainer,
                    {
                        transform: [{ scale: scaleAnim }],
                        borderColor: theme.primary,
                        backgroundColor: theme.surface,
                        shadowColor: theme.secondary
                    }
                ]}>
                    <Text style={{ fontSize: 80 }}>🛡️</Text>
                </Animated.View>

                {/* XP Animation */}
                <Animated.View style={{ opacity: fadeAnim, alignItems: 'center', marginBottom: 50 }}>
                    <Text style={[styles.xpValue, { color: theme.secondary }]}>+{xp} XP</Text>
                    <Text style={[styles.xpLabel, { color: theme.text }]}>ADICIONADO AO PERFIL</Text>
                </Animated.View>

                <TouchableOpacity
                    style={[styles.primaryButton, { backgroundColor: theme.btnPrimary || '#3A4A28' }]} // Safe Access or Fallback
                    onPress={() => router.replace('/(protected)/ranking')}
                >
                    <Text style={[styles.buttonText, { color: theme.text }]}>VER RANKING</Text>
                </TouchableOpacity>

                <TouchableOpacity
                    style={[styles.secondaryButton, { backgroundColor: theme.btnSecondary || '#2C2C2C' }]}
                    onPress={() => router.replace('/(protected)/painel')}
                >
                    <Text style={[styles.buttonText, { color: '#AAA' }]}>VOLTAR AO QG</Text>
                </TouchableOpacity>
            </View>
        </SafeAreaView>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        justifyContent: 'center',
        padding: 30,
    },
    content: {
        alignItems: 'center',
        width: '100%',
    },
    title: {
        fontSize: 28,
        fontWeight: '900',
        marginBottom: 40,
        letterSpacing: 2,
        textAlign: 'center',
    },
    shieldContainer: {
        width: 200,
        height: 200, // Large Icon
        borderRadius: 100,
        borderWidth: 6,
        justifyContent: 'center',
        alignItems: 'center',
        marginBottom: 30,
        elevation: 10,
        shadowOffset: { width: 0, height: 4 },
        shadowOpacity: 0.5,
        shadowRadius: 10,
    },
    xpValue: {
        fontSize: 40,
        fontWeight: '900',
        marginBottom: 5,
    },
    xpLabel: {
        fontSize: 12,
        letterSpacing: 2,
        fontWeight: '700',
    },
    primaryButton: {
        width: '100%',
        padding: 20,
        borderRadius: 12,
        alignItems: 'center',
        marginBottom: 15,
        elevation: 4,
    },
    secondaryButton: {
        width: '100%',
        padding: 20,
        borderRadius: 12,
        alignItems: 'center',
    },
    buttonText: {
        fontWeight: '700',
        fontSize: 14,
        letterSpacing: 1,
    }
});
