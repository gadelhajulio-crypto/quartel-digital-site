import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, ActivityIndicator } from 'react-native';
import { theme } from '../theme';
import { supabase } from '../../_lib/supabase';

export function TacticalLibrary() {
    const [isUnlocked, setIsUnlocked] = useState<boolean | null>(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        checkAccess();
    }, []);

    async function checkAccess() {
        try {
            // const { data, error } = await supabase.rpc('check_total_release');
            // if (error) throw error;
            setIsUnlocked(true); // Temp bypass
        } catch (error) {
            console.error('Erro ao verificar liberação total:', error);
            setIsUnlocked(false);
        } finally {
            setLoading(false);
        }
    }

    if (loading) {
        return <ActivityIndicator color={theme.colors.gold} />;
    }

    return (
        <View style={styles.container}>
            <View style={styles.header}>
                <Text style={styles.title}>BIBLIOTECA TÁTICA</Text>
                <Text style={styles.status}>
                    {isUnlocked ? 'ACESSO TOTAL LIBERADO' : 'ACESSO RESTRITO'}
                </Text>
            </View>

            <View style={styles.content}>
                <Text style={styles.description}>
                    {isUnlocked
                        ? 'Todos os módulos de inteligência e estratégia estão disponíveis para seu treinamento.'
                        : 'O acesso completo ao arsenal de conhecimento será liberado após 7 dias de serviço.'}
                </Text>
                {/* Aqui viriam os módulos ou links */}
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        backgroundColor: theme.colors.oliveGreen,
        borderRadius: 8,
        borderWidth: 1,
        borderColor: theme.colors.matteBlack,
        padding: theme.spacing.m,
        marginVertical: theme.spacing.s,
        elevation: 4, // Sombra Android
        shadowColor: '#000', // Sombra iOS
        shadowOffset: { width: 0, height: 2 },
        shadowOpacity: 0.25,
        shadowRadius: 3.84,
    },
    header: {
        borderBottomWidth: 1,
        borderBottomColor: theme.colors.gold,
        marginBottom: theme.spacing.s,
        paddingBottom: theme.spacing.s,
    },
    title: {
        fontSize: theme.typography.header.fontSize,
        fontWeight: 'bold', // Forçando tipo compatível
        color: theme.colors.gold,
        textTransform: 'uppercase',
    },
    status: {
        fontSize: 12,
        color: theme.colors.matteBlack,
        fontWeight: 'bold',
        marginTop: 4,
    },
    content: {
        marginTop: theme.spacing.s,
    },
    description: {
        fontSize: theme.typography.body.fontSize,
        color: theme.colors.white,
    },
});
