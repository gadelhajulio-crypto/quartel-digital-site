import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { VideoPlayer } from '../VideoPlayer';
import { theme } from '../../theme';

interface VideoCardProps {
    uri?: string;
    blocked: boolean;
}

export function VideoCard({ uri, blocked }: VideoCardProps) {
    return (
        <View style={[styles.card, { opacity: blocked ? 0.4 : 1 }]}>
            <Text style={styles.title}>🎥 Vídeo da Aula</Text>
            {blocked ? (
                <View style={styles.placeholder}>
                    <Ionicons name="lock-closed" size={24} color={theme.colors.textSecondary} />
                </View>
            ) : (
                uri ? <VideoPlayer uri={uri} /> : <Text style={styles.errorText}>Vídeo indisponível</Text>
            )}
        </View>
    );
}

const styles = StyleSheet.create({
    card: {
        marginBottom: 20,
    },
    title: {
        color: theme.colors.textPrimary,
        fontSize: 16,
        marginBottom: 8,
        fontWeight: 'bold',
    },
    placeholder: {
        height: 200,
        backgroundColor: theme.colors.card,
        borderRadius: 8,
        justifyContent: 'center',
        alignItems: 'center',
    },
    errorText: {
        color: theme.colors.textSecondary,
        fontStyle: 'italic',
    }
});
