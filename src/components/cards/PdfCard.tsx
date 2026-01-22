import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { theme } from '../../theme';
import * as Linking from 'expo-linking';

interface PdfCardProps {
    blocked: boolean;
    uri?: string;
}

export function PdfCard({ blocked, uri }: PdfCardProps) {
    const handlePress = () => {
        if (!blocked && uri) {
            Linking.openURL(uri).catch(err => console.error("Could not open PDF", err));
        }
    };

    return (
        <TouchableOpacity
            style={[styles.container, { opacity: blocked ? 0.4 : 1 }]}
            onPress={blocked ? undefined : handlePress}
            activeOpacity={blocked ? 1 : 0.7}
            disabled={blocked || !uri}
        >
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                <Ionicons name="document-text" size={20} color={theme.colors.textPrimary} />
                <Text style={styles.title}>📄 PDF Complementar</Text>
            </View>
            {blocked ? (
                <Ionicons name="lock-closed" size={20} color={theme.colors.textSecondary} />
            ) : (
                <Ionicons name="open-outline" size={20} color={theme.colors.textPrimary} />
            )}
        </TouchableOpacity>
    );
}

const styles = StyleSheet.create({
    container: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: 16,
        backgroundColor: theme.colors.card,
        borderRadius: 8,
        marginBottom: 16,
    },
    title: {
        color: theme.colors.textPrimary,
        fontWeight: 'bold',
    }
});
