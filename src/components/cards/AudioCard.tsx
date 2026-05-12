import React from 'react';
import { View, Text, Button, StyleSheet, TouchableOpacity } from 'react-native';
import { Audio } from 'expo-av';
import { theme } from '../../theme';
import { Ionicons } from '@expo/vector-icons';

interface AudioCardProps {
    uri?: string;
    blocked: boolean;
}

export function AudioCard({ uri, blocked }: AudioCardProps) {
    async function play() {
        if (!uri) return;
        try {
            const { sound } = await Audio.Sound.createAsync({ uri });
            await sound.playAsync();
        } catch (e) {
            console.warn("Audio playback failed", e);
        }
    }

    return (
        <View style={[styles.container, { opacity: blocked ? 0.4 : 1 }]}>
            <Text style={styles.title}>🎧 Revisão em Áudio</Text>
            {!blocked && uri && (
                <TouchableOpacity onPress={play} style={styles.button}>
                    <Ionicons name="play" size={24} color={theme.colors.background} />
                    <Text style={styles.buttonText}>Ouvir</Text>
                </TouchableOpacity>
            )}
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        padding: 16,
        backgroundColor: theme.colors.card,
        borderRadius: 8,
        marginBottom: 16,
    },
    title: {
        color: theme.colors.textPrimary,
        fontWeight: 'bold',
        marginBottom: 12,
    },
    button: {
        flexDirection: 'row',
        backgroundColor: theme.colors.gold || '#FFD166',
        padding: 12,
        borderRadius: 8,
        alignItems: 'center',
        justifyContent: 'center',
        gap: 8,
    },
    buttonText: {
        color: theme.colors.background,
        fontWeight: 'bold',
    }
});
