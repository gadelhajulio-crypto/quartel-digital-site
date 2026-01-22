import React from 'react';
import { TouchableOpacity, Text, StyleSheet, View } from 'react-native';
import { theme } from '../theme';

type FileDownloadButtonProps = {
    title: string;
    onPress?: () => void;
    color?: string; // Force theme color
};

export function FileDownloadButton({ title, onPress, color = theme.colors.oliveGreen }: FileDownloadButtonProps) {
    return (
        <TouchableOpacity
            style={[styles.container, { borderColor: color, backgroundColor: 'rgba(255,255,255,0.05)' }]}
            onPress={onPress}
        >
            <View style={styles.iconContainer}>
                <Text style={styles.icon}>📄</Text>
            </View>
            <View style={styles.textContainer}>
                <Text style={styles.label}>MATERIAL DE APOIO</Text>
                <Text style={[styles.title, { color: theme.colors.white }]}>{title}</Text>
            </View>
            <View style={styles.downloadIcon}>
                <Text style={{ color: color, fontSize: 18 }}>⬇️</Text>
            </View>
        </TouchableOpacity>
    );
}

const styles = StyleSheet.create({
    container: {
        flexDirection: 'row',
        alignItems: 'center',
        padding: theme.spacing.m,
        borderRadius: 6,
        borderWidth: 1,
        marginBottom: theme.spacing.s,
    },
    iconContainer: {
        marginRight: theme.spacing.m,
    },
    icon: {
        fontSize: 24,
    },
    textContainer: {
        flex: 1,
    },
    label: {
        fontSize: 10,
        color: '#AAA',
        letterSpacing: 1,
        marginBottom: 2,
    },
    title: {
        fontSize: 14,
        fontWeight: 'bold',
    },
    downloadIcon: {
        marginLeft: theme.spacing.m,
    }
});
