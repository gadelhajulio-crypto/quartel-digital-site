import { View, Text, StyleSheet, FlatList } from 'react-native';
import { useAuth } from '../../../src/context/AuthContext';
import { useForceTheme } from '../../../src/context/ForceThemeContext';
import { HierarchyBadge } from '../../../src/components/HierarchyBadge';
import { useMedals } from '../../../src/hooks/useMedals';

export default function PerfilScreen() {
    const { profile } = useAuth();
    const { theme } = useForceTheme();
    const { medals } = useMedals();

    if (!profile) {
        return (
            <View style={[styles.container, { backgroundColor: theme.background }]}>
                <Text style={{ color: theme.text }}>Carregando perfil…</Text>
            </View>
        );
    }

    const conqueredMedals = medals.filter((m) => m.achieved);

    return (
        <View style={[styles.container, { backgroundColor: theme.background }]}>
            {/* Header institucional */}
            <Text style={[styles.header, { color: theme.primary }]}>
                Perfil do Recruta
            </Text>

            {/* Identificação */}
            <View style={styles.section}>
                <Text style={[styles.name, { color: theme.text }]}>
                    {profile.nome}
                </Text>

                <Text style={[styles.force, { color: theme.muted }]}>
                    Força: {profile.forca.toUpperCase()}
                </Text>
            </View>

            {/* Hierarquia */}
            <View style={styles.section}>
                <Text style={[styles.sectionTitle, { color: theme.text }]}>
                    Hierarquia Atual
                </Text>

                <HierarchyBadge nivelAtual={profile.nivel_atual} />
            </View>

            {/* Medalhas conquistadas */}
            <View style={styles.section}>
                <Text style={[styles.sectionTitle, { color: theme.text }]}>
                    Medalhas Conquistadas
                </Text>

                {conqueredMedals.length === 0 ? (
                    <Text style={{ color: theme.muted }}>
                        Nenhuma medalha conquistada até o momento.
                    </Text>
                ) : (
                    <FlatList
                        data={conqueredMedals}
                        keyExtractor={(item) => item.medal_id}
                        renderItem={({ item }) => (
                            <Text style={[styles.medalItem, { color: theme.text }]}>
                                • {item.name}
                            </Text>
                        )}
                    />
                )}
            </View>
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
        marginBottom: 20,
    },
    section: {
        marginBottom: 24,
    },
    name: {
        fontSize: 18,
        fontWeight: '600',
        marginBottom: 4,
    },
    force: {
        fontSize: 14,
    },
    sectionTitle: {
        fontSize: 16,
        fontWeight: '600',
        marginBottom: 8,
    },
    medalItem: {
        fontSize: 14,
        marginBottom: 4,
    },
});
