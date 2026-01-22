import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { theme } from '../../theme';
import { Ionicons } from '@expo/vector-icons';

export function StatusBadge({ isChampion }: { isChampion: boolean }) {
    return (
        <View style={[styles.badge, isChampion ? styles.champion : styles.progress]}>
            {isChampion && <Ionicons name="trophy" size={16} color="#000" style={{ marginRight: 6 }} />}
            <Text style={[styles.text, isChampion && { color: '#000' }]}>
                {isChampion ? 'Campeão Mensal' : 'Em Progresso'}
            </Text>
        </View>
    );
}

const styles = StyleSheet.create({
    badge: {
        paddingVertical: 8,
        paddingHorizontal: 16,
        borderRadius: 20,
        alignSelf: 'flex-start',
        marginTop: 8,
        flexDirection: 'row',
        alignItems: 'center',
    },
    champion: {
        backgroundColor: theme.colors.gold || '#FFD166',
    },
    progress: {
        backgroundColor: theme.colors.surface,
        borderWidth: 1,
        borderColor: theme.colors.border,
    },
    text: {
        color: theme.colors.textPrimary,
        fontWeight: 'bold',
        fontSize: 14,
    }
});
