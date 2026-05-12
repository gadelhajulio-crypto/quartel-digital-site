import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet, SafeAreaView } from 'react-native';
import { InstitutionalEvent } from '../../types/institutionalEvents';
import { theme } from '../../theme';

export function PromotionScreen({ event, onFinish }: { event: InstitutionalEvent, onFinish: () => void }) {
    const isGrade6 = event.priority === 1;

    return (
        <SafeAreaView style={styles.container}>
            <View style={styles.content}>
                <Text style={[styles.title, isGrade6 && { color: 'red' }]}>
                    {isGrade6 ? 'PROMOÇÃO MÁXIMA' : 'PROMOÇÃO DE GRAU'}
                </Text>
                <Text style={styles.subtitle}>Avanço na Hierarquia</Text>

                <View style={styles.badgePlaceholder}>
                    <Text style={{ color: '#FFF' }}>⭐</Text>
                </View>

                <Text style={styles.details}>
                    Pelo cumprimento dos deveres e honra ao mérito.
                </Text>
            </View>

            <TouchableOpacity style={styles.button} onPress={onFinish}>
                <Text style={styles.buttonText}>CIENTE</Text>
            </TouchableOpacity>
        </SafeAreaView>
    );
}

const styles = StyleSheet.create({
    container: { flex: 1, backgroundColor: '#05101A', padding: 20 },
    content: { flex: 1, justifyContent: 'center', alignItems: 'center' },
    title: { color: theme.colors.gold, fontSize: 24, fontWeight: 'bold', marginBottom: 10, textAlign: 'center' },
    subtitle: { color: '#AAA', fontSize: 16, marginBottom: 40 },
    badgePlaceholder: { width: 120, height: 120, borderRadius: 8, backgroundColor: '#2A3B4C', justifyContent: 'center', alignItems: 'center', marginBottom: 30 },
    details: { color: '#FFF', fontSize: 16, textAlign: 'center', paddingHorizontal: 20 },
    button: { backgroundColor: theme.colors.gold, padding: 16, borderRadius: 8, alignItems: 'center', marginBottom: 20 },
    buttonText: { fontWeight: 'bold', color: '#000' }
});
