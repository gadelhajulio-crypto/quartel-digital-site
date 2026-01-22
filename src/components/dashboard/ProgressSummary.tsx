import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useForceTheme } from '../../context/ForceThemeContext';
import { useAuth } from '../../context/AuthContext';

export default function ProgressSummary() {
    const { theme } = useForceTheme();
    const { profile } = useAuth();

    return (
        <View style={[styles.container, { backgroundColor: theme.card, borderLeftColor: theme.accent }]}>
            {/* COLUMN 1: XP */}
            <View style={styles.column}>
                <Text style={styles.value}>{profile?.xp ?? 0}</Text>
                <Text style={styles.label}>XP TOTAL</Text>
            </View>

            <View style={styles.separator} />

            {/* COLUMN 2: CONSTÂNCIA (Mocked for now as per instructions usually, or use 0) */}
            <View style={styles.column}>
                <Text style={styles.value}>0</Text>
                <Text style={styles.label}>DIAS</Text>
            </View>

            <View style={styles.separator} />

            {/* COLUMN 3: MEDALS */}
            <View style={styles.column}>
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 4 }}>
                    <Ionicons name="ribbon" size={16} color={theme.accent} />
                    <Text style={styles.value}>0</Text>
                </View>
                <Text style={styles.label}>MEDALHAS</Text>
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flexDirection: 'row',
        borderRadius: 12,
        padding: 20,
        marginBottom: 24,
        borderLeftWidth: 4,
        justifyContent: 'space-between',
        alignItems: 'center',
    },
    column: {
        alignItems: 'center',
        flex: 1,
    },
    value: {
        color: '#FFF',
        fontSize: 20,
        fontWeight: 'bold',
        marginBottom: 4,
    },
    label: {
        color: '#666',
        fontSize: 10,
        fontWeight: 'bold',
        letterSpacing: 1,
    },
    separator: {
        width: 1,
        height: 24,
        backgroundColor: 'rgba(255,255,255,0.1)',
    },
});
