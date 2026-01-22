import React from 'react';
import { View, Text, StyleSheet, ScrollView } from 'react-native';
import { theme } from '../theme';

export function SinoDeBordo() {
    return (
        <View style={styles.container}>
            <View style={styles.bellContainer}>
                <Text style={styles.bellIcon}>🔔</Text>
            </View>
            <Text style={styles.title}>SINO DE BORDO</Text>

            <View style={styles.board}>
                <View style={styles.notice}>
                    <Text style={styles.noticeTitle}>AVISO DE COMANDO</Text>
                    <Text style={styles.noticeDate}>14 JAN 2026</Text>
                    <Text style={styles.noticeBody}>
                        O portal web está operando com novo design naval.
                        Mantenha suas credenciais seguras.
                    </Text>
                </View>

                <View style={styles.notice}>
                    <Text style={styles.noticeTitle}>INÍCIO DOS JOGOS</Text>
                    <Text style={styles.noticeDate}>10 JAN 2026</Text>
                    <Text style={styles.noticeBody}>
                        Todos os recrutas devem completar o Módulo Básico até sexta-feira.
                    </Text>
                </View>
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        backgroundColor: theme.colors.matteBlack,
        padding: theme.spacing.m,
        borderRadius: 8,
        borderWidth: 2,
        borderColor: theme.colors.oliveGreen,
        alignItems: 'center',
    },
    bellContainer: {
        marginBottom: theme.spacing.s,
    },
    bellIcon: {
        fontSize: 40,
    },
    title: {
        color: theme.colors.gold,
        fontSize: theme.typography.header.fontSize,
        fontWeight: 'bold',
        marginBottom: theme.spacing.l,
        letterSpacing: 2,
    },
    board: {
        width: '100%',
        gap: theme.spacing.m,
    },
    notice: {
        backgroundColor: 'rgba(75, 83, 32, 0.3)', // Olive transparent
        padding: theme.spacing.m,
        borderRadius: 4,
        borderLeftWidth: 4,
        borderLeftColor: theme.colors.gold,
    },
    noticeTitle: {
        color: theme.colors.white,
        fontWeight: 'bold',
        fontSize: 16,
        marginBottom: 4,
    },
    noticeDate: {
        color: '#AAA',
        fontSize: 12,
        marginBottom: 8,
    },
    noticeBody: {
        color: '#DDD',
        fontSize: 14,
        lineHeight: 20,
    },
});
