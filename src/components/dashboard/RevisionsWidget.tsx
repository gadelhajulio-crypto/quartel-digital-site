import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { useForceTheme } from '../../context/ForceThemeContext';
import { Ionicons } from '@expo/vector-icons';

interface RevisionsWidgetProps {
    count: number;
    onPress: () => void;
}

export function RevisionsWidget({ count, onPress }: RevisionsWidgetProps) {
    const { theme, force } = useForceTheme();

    return (
        <TouchableOpacity
            style={[styles.container, { backgroundColor: theme.dashboard.card, borderBottomColor: theme.dashboard.border }]}
            onPress={onPress}
        >
            <View style={styles.leftContent}>
                <Ionicons name="book-outline" size={22} color={theme.dashboard.accent} style={{ marginRight: 12 }} />
                <Text style={[styles.title, { color: theme.dashboard.textPrimary }]}>
                    Revisões diárias
                </Text>
            </View>

            <View style={styles.rightContent}>
                {count > 0 && (
                    <View style={[styles.badge, { backgroundColor: theme.dashboard.accent }]}>
                        <Text style={styles.badgeText}>{count} novas</Text>
                    </View>
                )}
                <Ionicons name="chevron-forward" size={16} color={theme.dashboard.textSecondary} style={{ marginLeft: 8 }} />
            </View>
        </TouchableOpacity>
    );
}

const styles = StyleSheet.create({
    container: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        paddingVertical: 16,
        paddingHorizontal: 20,
        borderBottomWidth: 1,
        marginBottom: 8,
    },
    leftContent: {
        flexDirection: 'row',
        alignItems: 'center',
    },
    title: {
        fontSize: 16,
        fontWeight: '500',
    },
    rightContent: {
        flexDirection: 'row',
        alignItems: 'center',
    },
    badge: {
        paddingHorizontal: 8,
        paddingVertical: 2,
        borderRadius: 12,
    },
    badgeText: {
        color: '#FFF',
        fontSize: 12,
        fontWeight: '600',
    }
});
