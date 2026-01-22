import { View, Text, StyleSheet, Switch, TouchableOpacity } from 'react-native';
import { useState } from 'react';
import { useRouter } from 'expo-router';
import { useForceTheme } from '../../../src/context/ForceThemeContext';

export default function ConfiguracoesScreen() {
    const { theme } = useForceTheme();
    const router = useRouter();

    const [soundEnabled, setSoundEnabled] = useState(true);
    const [vibrationEnabled, setVibrationEnabled] = useState(true);

    const toggleSound = (value: boolean) => {
        setSoundEnabled(value);
    };

    const toggleVibration = (value: boolean) => {
        setVibrationEnabled(value);
    };

    return (
        <View style={[styles.container, { backgroundColor: theme.background }]}>
            {/* Header */}
            <Text style={[styles.header, { color: theme.primary }]}>
                Configurações
            </Text>

            {/* Preferências */}
            <Text style={[styles.sectionTitle, { color: theme.muted }]}>
                Preferências
            </Text>

            <View style={[styles.row, { borderColor: theme.border }]}>
                <Text style={[styles.label, { color: theme.text }]}>
                    Som do app
                </Text>
                <Switch
                    value={soundEnabled}
                    onValueChange={toggleSound}
                    trackColor={{ true: theme.primary }}
                />
            </View>

            <View style={[styles.row, { borderColor: theme.border }]}>
                <Text style={[styles.label, { color: theme.text }]}>
                    Vibração
                </Text>
                <Switch
                    value={vibrationEnabled}
                    onValueChange={toggleVibration}
                    trackColor={{ true: theme.primary }}
                />
            </View>

            {/* Institucional */}
            <Text style={[styles.sectionTitle, { color: theme.muted, marginTop: 32 }]}>
                Institucional
            </Text>

            <TouchableOpacity
                style={[styles.linkRow, { borderColor: theme.border }]}
                onPress={() => router.push('/termos')}
            >
                <Text style={[styles.linkText, { color: theme.text }]}>
                    Termos de Uso
                </Text>
            </TouchableOpacity>

            <TouchableOpacity
                style={[styles.linkRow, { borderColor: theme.border }]}
                onPress={() => router.push('/privacidade')}
            >
                <Text style={[styles.linkText, { color: theme.text }]}>
                    Privacidade e Uso de Dados
                </Text>
            </TouchableOpacity>

            <TouchableOpacity
                style={[styles.linkRow, { borderColor: theme.border }]}
                onPress={() => router.push('/sobre')}
            >
                <Text style={[styles.linkText, { color: theme.text }]}>
                    Sobre o Quartel Digital
                </Text>
            </TouchableOpacity>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        padding: 16,
    },
    header: {
        fontSize: 20,
        fontWeight: '600',
        marginBottom: 24,
    },
    sectionTitle: {
        fontSize: 13,
        marginBottom: 12,
        textTransform: 'uppercase',
    },
    row: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        paddingVertical: 14,
        borderBottomWidth: 1,
    },
    label: {
        fontSize: 15,
    },
    linkRow: {
        paddingVertical: 14,
        borderBottomWidth: 1,
    },
    linkText: {
        fontSize: 15,
    },
});
