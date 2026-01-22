import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { theme } from '../../theme';

export function IndicatorCard({ label, value }: { label: string, value: string | number }) {
    return (
        <View style={styles.card}>
            <Text style={styles.label}>{label}</Text>
            <Text style={styles.value}>{value}</Text>
        </View>
    );
}

const styles = StyleSheet.create({
    card: {
        padding: 16,
        borderRadius: 12,
        backgroundColor: theme.colors.card, // Using theme card color
        marginBottom: 12,
        alignItems: 'center',
        justifyContent: 'center',
        minWidth: '30%',
        flex: 1,
        marginHorizontal: 4,
    },
    label: {
        color: theme.colors.textSecondary,
        fontSize: 12,
        marginBottom: 4,
        textAlign: 'center',
    },
    value: {
        color: theme.colors.textPrimary,
        fontSize: 20,
        fontWeight: 'bold',
    }
});
