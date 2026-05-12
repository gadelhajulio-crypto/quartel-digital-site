import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet, SafeAreaView } from 'react-native';
import { InstitutionalEvent } from '../../types/institutionalEvents';
import { theme } from '../../theme';

export function MedalScreen({ event, onFinish }: { event: InstitutionalEvent, onFinish: () => void }) {
    return (
        <SafeAreaView style={styles.container}>
            <View style={styles.content}>
                <Text style={styles.title}>CONCESSÃO DE MEDALHA</Text>
                <Text style={styles.subtitle}>Reconhecimento Institucional</Text>

                <View style={styles.badgePlaceholder}>
                    <Text style={{ color: '#FFF' }}>🏅</Text>
                </View>

                {/* Dados mockados do payload ou genéricos se não houver */}
                <Text style={styles.medalName}>
                    {event.payload?.title || 'Medalha de Honra'}
                </Text>
            </View>

            <TouchableOpacity style={styles.button} onPress={onFinish}>
                <Text style={styles.buttonText}>RECEBER</Text>
            </TouchableOpacity>
        </SafeAreaView>
    );
}

const styles = StyleSheet.create({
    container: { flex: 1, backgroundColor: '#1A1A1A', padding: 20 },
    content: { flex: 1, justifyContent: 'center', alignItems: 'center' },
    title: { color: theme.colors.gold, fontSize: 24, fontWeight: 'bold', marginBottom: 10, textAlign: 'center' },
    subtitle: { color: '#AAA', fontSize: 16, marginBottom: 40 },
    badgePlaceholder: { width: 120, height: 120, borderRadius: 60, backgroundColor: '#333', justifyContent: 'center', alignItems: 'center', marginBottom: 30 },
    medalName: { color: '#FFF', fontSize: 20, fontWeight: '600' },
    button: { backgroundColor: theme.colors.gold, padding: 16, borderRadius: 8, alignItems: 'center', marginBottom: 20 },
    buttonText: { fontWeight: 'bold', color: '#000' }
});
