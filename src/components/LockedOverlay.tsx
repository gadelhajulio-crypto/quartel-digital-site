import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { theme } from '../theme';

export function LockedOverlay() {
    return (
        <View style={styles.container}>
            <Ionicons name="lock-closed" size={32} color={theme.colors.textSecondary} />
            <Text style={styles.text}>Conteúdo Bloqueado</Text>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        ...StyleSheet.absoluteFillObject,
        backgroundColor: 'rgba(0,0,0,0.6)',
        justifyContent: 'center',
        alignItems: 'center',
        zIndex: 10,
        borderRadius: 8,
    },
    text: {
        color: theme.colors.textSecondary,
        marginTop: 8,
        fontSize: 14,
        fontWeight: 'bold',
    },
});
