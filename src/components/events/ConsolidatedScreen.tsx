import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet, SafeAreaView } from 'react-native';
import { InstitutionalEvent } from '../../types/institutionalEvents';
import { theme } from '../../theme';

export function ConsolidatedScreen({ event, onFinish }: { event: InstitutionalEvent, onFinish: () => void }) {
    return (
        <SafeAreaView style={styles.container}>
            <View style={styles.content}>
                <Text style={styles.title}>CONQUISTA SIMULTÂNEA</Text>
                <Text style={styles.subtitle}>Reconhecimento Duplo</Text>

                <View style={styles.row}>
                    <View style={styles.card}>
                        <Text style={styles.icon}>medalha</Text>
                        <Text style={styles.label}>Nova Medalha</Text>
                    </View>
                    <Text style={styles.plus}>+</Text>
                    <View style={styles.card}>
                        <Text style={styles.icon}>grau</Text>
                        <Text style={styles.label}>Novo Grau</Text>
                    </View>
                </View>

                <Text style={styles.details}>
                    Sua dedicação gerou múltiplos reconhecimentos neste ciclo.
                </Text>
            </View>

            <TouchableOpacity style={styles.button} onPress={onFinish}>
                <Text style={styles.buttonText}>RECEBER HONRARIAS</Text>
            </TouchableOpacity>
        </SafeAreaView>
    );
}

const styles = StyleSheet.create({
    container: { flex: 1, backgroundColor: '#111', padding: 20 },
    content: { flex: 1, justifyContent: 'center', alignItems: 'center' },
    title: { color: theme.colors.gold, fontSize: 24, fontWeight: 'bold', marginBottom: 10 },
    subtitle: { color: '#AAA', fontSize: 16, marginBottom: 40 },
    row: { flexDirection: 'row', alignItems: 'center', marginBottom: 40 },
    card: { width: 100, height: 120, backgroundColor: '#222', borderRadius: 8, justifyContent: 'center', alignItems: 'center' },
    icon: { color: '#FFF', marginBottom: 10 },
    label: { color: '#AAA', fontSize: 12 },
    plus: { color: theme.colors.gold, fontSize: 32, marginHorizontal: 20 },
    details: { color: '#FFF', textAlign: 'center' },
    button: { backgroundColor: theme.colors.gold, padding: 16, borderRadius: 8, alignItems: 'center', marginBottom: 20, width: '100%' },
    buttonText: { fontWeight: 'bold', color: '#000' }
});
