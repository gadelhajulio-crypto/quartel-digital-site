import React, { useEffect, useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Linking, Image } from 'react-native';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useForceTheme } from '../../context/ForceThemeContext';
import { supabase } from '../../lib/supabase';

type Module = {
    id: string;
    titulo: string;
    descricao: string;
    thumbnail_url?: string;
    bloqueado?: boolean; // If true -> "Saiba mais" (Link)
    link_externo?: string;
};

export default function InstructionsInProgress() {
    const { theme } = useForceTheme();
    const router = useRouter();
    const [modules, setModules] = useState<Module[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        loadModules();
    }, []);

    async function loadModules() {
        try {
            // Fetch modules, limit 3. 
            // Priority: 'ordem' for now as 'last accessed' requires tracking table not fully detailed here.
            // Converting 'ativa' or 'bloqueado' logic. 
            // Assuming 'modulos' table.

            const { data, error } = await supabase
                .from('v_modulos_catalogo')
                .select('*')
                .eq('publicado', true)
                .order('ordem', { ascending: true })
                .limit(3);

            if (data) {
                // Determine if blocked based on logic (hardcoded or from DB).
                // For now, assume all open unless 'degustacao' logic applies?
                // Request says: "If module is blocked (degustation), button says 'Saiba mais'".
                // We'll simulate this property or map it if exists.
                // Let's assume 'bloqueado' isn't a column yet, so we treat everything as 'Continuar' 
                // UNLESS title implies locked or we add logic later.
                // For safety, I will treat them as 'open' for navigation instructions 
                // but add a mock visual check if needed.
                // Actually, the user prompts implied a 'degustação' flag logic previously.
                // I will map the DB data directly.
                setModules(data);
            }
        } catch (e) {
            console.error(e);
        } finally {
            setLoading(false);
        }
    }

    function handlePress(mod: Module) {
        if (mod.bloqueado) {
            if (mod.link_externo) {
                Linking.openURL(mod.link_externo);
            } else {
                // Fallback link
                Linking.openURL('https://quarteldigital.com.br');
            }
        } else {
            router.push(`/modulo/${mod.id}`);
        }
    }

    if (loading) return null;

    if (modules.length === 0) {
        return (
            <View style={[styles.emptyState, { backgroundColor: theme.card }]}>
                <Text style={{ color: theme.textSecondary }}>Nenhuma instrução em andamento.</Text>
            </View>
        );
    }

    return (
        <View>
            <View style={styles.header}>
                <Text style={[styles.title, { color: theme.textSecondary }]}>INSTRUÇÕES EM ANDAMENTO</Text>
            </View>

            {modules.map((mod) => (
                <View key={mod.id} style={[styles.card, { backgroundColor: theme.card }]}>
                    <View style={styles.info}>
                        <Text style={[styles.moduleTitle, { color: theme.textPrimary }]}>{mod.titulo}</Text>
                        <Text style={[styles.moduleDesc, { color: theme.textSecondary }]} numberOfLines={1}>
                            {mod.descricao}
                        </Text>
                    </View>

                    <TouchableOpacity
                        style={[
                            styles.button,
                            {
                                backgroundColor: mod.bloqueado ? 'transparent' : theme.accent,
                                borderWidth: mod.bloqueado ? 1 : 0,
                                borderColor: mod.bloqueado ? theme.textSecondary : 'transparent'
                            }
                        ]}
                        onPress={() => handlePress(mod)}
                    >
                        <Text style={[
                            styles.buttonText,
                            { color: mod.bloqueado ? theme.textSecondary : theme.background }
                        ]}>
                            {mod.bloqueado ? 'SAIBA MAIS' : 'CONTINUAR'}
                        </Text>
                        {!mod.bloqueado && (
                            <Ionicons name="play" size={14} color={theme.background} />
                        )}
                    </TouchableOpacity>
                </View>
            ))}
        </View>
    );
}

const styles = StyleSheet.create({
    header: {
        marginBottom: 12,
        marginTop: 8,
    },
    title: {
        fontSize: 12,
        fontWeight: 'bold',
        letterSpacing: 1,
    },
    emptyState: {
        padding: 20,
        borderRadius: 12,
        alignItems: 'center',
    },
    card: {
        padding: 16,
        borderRadius: 12,
        marginBottom: 12,
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
        gap: 12,
    },
    info: {
        flex: 1,
    },
    moduleTitle: {
        fontSize: 14,
        fontWeight: 'bold',
        marginBottom: 4,
        textTransform: 'uppercase',
    },
    moduleDesc: {
        fontSize: 12,
    },
    button: {
        paddingVertical: 10,
        paddingHorizontal: 16,
        borderRadius: 8,
        flexDirection: 'row',
        alignItems: 'center',
        gap: 6,
    },
    buttonText: {
        fontSize: 10,
        fontWeight: 'bold',
        letterSpacing: 0.5,
    },
});
