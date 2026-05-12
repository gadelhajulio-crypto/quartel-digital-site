import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet, SafeAreaView } from 'react-native';
import { theme } from '../../theme';

export function InstitutionalErrorScreen({ onClose }: { onClose: () => void }) {
    return (
        <SafeAreaView style={styles.container}>
            <View style={styles.content}>
                <Text style={styles.title}>ERRO TÉCNICO</Text>
                <Text style={styles.details}>
                    Houve uma falha na apresentação do evento institucional.
                </Text>
            </View>

            <TouchableOpacity style={styles.button} onPress={onClose}>
                <Text style={styles.buttonText}>FECHAR</Text>
            </TouchableOpacity>
        </SafeAreaView>
    );
}

const styles = StyleSheet.create({
    container: { flex: 1, backgroundColor: '#000', padding: 20 },
    content: { flex: 1, justifyContent: 'center', alignItems: 'center' },
    title: { color: 'red', fontSize: 24, fontWeight: 'bold', marginBottom: 20 },
    details: { color: '#AAA', textAlign: 'center' },
    button: { borderColor: '#AAA', borderWidth: 1, padding: 16, borderRadius: 8, alignItems: 'center', marginBottom: 20, width: '100%' },
    buttonText: { color: '#AAA' }
});
