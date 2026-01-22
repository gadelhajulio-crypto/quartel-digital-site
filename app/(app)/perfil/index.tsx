import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { useRouter } from 'expo-router';
import { useAuth } from '../../../src/context/AuthContext';
import { useForceTheme } from '../../../src/context/ForceThemeContext';
import { HierarchyBadge } from '../../../src/components/HierarchyBadge';

export default function PerfilScreen() {
    const { theme } = useForceTheme();
    const { profile } = useAuth();
    const router = useRouter();

    if (!profile) {
        return null;
    }

    return (
        <View style={[styles.container, { backgroundColor: theme.background }]}>
            {/* Header institucional */}
            <Text style={[styles.header, { color: theme.primary }]}>
                Perfil do Recruta
            </Text>

            {/* Identificação */}
            <View style={styles.section}>
                <Text style={[styles.label, { color: theme.muted }]}>Nome</Text>
                <Text style={[styles.value, { color: theme.text }]}>
                    {profile.nome}
                </Text>
            </View>

            <View style={styles.section}>
                <Text style={[styles.label, { color: theme.muted }]}>Força</Text>
                <Text style={[styles.value, { color: theme.text }]}>
                    {profile.forca.toUpperCase()}
                </Text>
            </View>

            {/* Hierarquia */}
            <View style={styles.section}>
                <Text style={[styles.label, { color: theme.muted }]}>
                    Hierarquia Atual
                </Text>
                <HierarchyBadge nivelAtual={profile.nivel_atual} />
            </View>

            {/* Medalhas (resumo institucional) */}
            <View style={styles.section}>
                <Text style={[styles.label, { color: theme.muted }]}>
                    Condecorações
                </Text>
                <Text style={[styles.value, { color: theme.text }]}>
                    Medalhas conquistadas disponíveis na seção dedicada
                </Text>
            </View>

            {/* 🔗 ACESSO AO HISTÓRICO */}
            <TouchableOpacity
                onPress={() => router.push('/historico')}
                style={[
                    styles.linkRow,
                    { borderColor: theme.border },
                ]}
            >
                <Text style={[styles.linkText, { color: theme.primary }]}>
                    Ver histórico completo
                </Text>
            </TouchableOpacity>

            {/* 🔗 ACESSO ÀS CONFIGURAÇÕES */}
            <TouchableOpacity
                onPress={() => router.push('/configuracoes')}
                style={[
                    styles.linkRow,
                    { borderColor: theme.border },
                ]}
            >
                <Text style={[styles.linkText, { color: theme.primary }]}>
                    Configurações
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
    section: {
        marginBottom: 18,
    },
    label: {
        fontSize: 13,
        marginBottom: 4,
    },
    value: {
        fontSize: 16,
        fontWeight: '500',
    },
    linkRow: {
        marginTop: 16,
        paddingVertical: 14,
        alignItems: 'center',
        borderTopWidth: 1,
    },
    linkText: {
        fontSize: 14,
        fontWeight: '500',
    },
});
