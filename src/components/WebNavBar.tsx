import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet, Platform, Image } from 'react-native';
import { Link } from 'expo-router';
import { theme } from '../theme';

export function WebNavBar() {
    if (Platform.OS !== 'web') return null;

    return (
        <View style={styles.container}>
            <View style={styles.logoContainer}>
                {/* Placeholder para Logo ou Texto */}
                <Text style={styles.logoText}>QUARTEL DIGITAL</Text>
            </View>

            <View style={styles.navLinks}>
                <Link href="/" asChild>
                    <TouchableOpacity style={styles.linkButton}>
                        <Text style={styles.linkText}>HOME</Text>
                    </TouchableOpacity>
                </Link>

                {/* Links placeholder - podem ser ajustados para rotas reais ou scroll */}
                <TouchableOpacity style={styles.linkButton}>
                    <Text style={styles.linkText}>QUARTEL DIGITAL</Text>
                </TouchableOpacity>

                <TouchableOpacity style={styles.linkButton}>
                    <Text style={styles.linkText}>BIBLIOTECA ESTRATÉGICA</Text>
                </TouchableOpacity>

                <TouchableOpacity style={styles.linkButton}>
                    <Text style={styles.linkText}>SINO DE BORDO</Text>
                </TouchableOpacity>

                <Link href="/login" asChild>
                    <TouchableOpacity style={[styles.linkButton, styles.ctaButton]}>
                        <Text style={styles.ctaText}>ÁREA DO RECRUTA</Text>
                    </TouchableOpacity>
                </Link>
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        paddingHorizontal: theme.spacing.xl,
        paddingVertical: theme.spacing.m,
        backgroundColor: theme.colors.matteBlack,
        borderBottomWidth: 2,
        borderBottomColor: theme.colors.oliveGreen,
        zIndex: 100,
    },
    logoContainer: {
        flexDirection: 'row',
        alignItems: 'center',
    },
    logoText: {
        fontSize: 20,
        fontWeight: 'bold',
        color: theme.colors.gold,
        letterSpacing: 2,
    },
    navLinks: {
        flexDirection: 'row',
        gap: theme.spacing.l,
        alignItems: 'center',
    },
    linkButton: {
        paddingVertical: theme.spacing.s,
        paddingHorizontal: theme.spacing.s,
    },
    linkText: {
        color: theme.colors.white,
        fontWeight: '600',
        fontSize: 14,
        textTransform: 'uppercase',
    },
    ctaButton: {
        backgroundColor: theme.colors.oliveGreen,
        paddingHorizontal: theme.spacing.m,
        paddingVertical: theme.spacing.s,
        borderRadius: 4,
        borderWidth: 1,
        borderColor: theme.colors.gold,
    },
    ctaText: {
        color: theme.colors.gold,
        fontWeight: 'bold',
        fontSize: 14,
        textTransform: 'uppercase',
    },
});
