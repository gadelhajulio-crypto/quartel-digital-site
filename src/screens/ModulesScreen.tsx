import React, { useEffect, useState } from 'react';
import {
    View,
    Text,
    FlatList,
    TouchableOpacity,
    StyleSheet,
    SafeAreaView,
    ActivityIndicator
} from 'react-native';
import { supabase } from '../lib/supabase';
import { useAuth } from '../context/AuthContext';
import { canAccessModule } from '../hooks/useModuleAccess';
import { theme } from '../theme'; // Using existing theme
import { useRouter } from 'expo-router';

type Modulo = {
    id: string;
    titulo: string;
    descricao: string;
    is_degustacao: boolean;
};

export default function ModulesScreen() {
    const router = useRouter();
    const { profile } = useAuth();
    const [modules, setModules] = useState<Modulo[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        loadModules();
    }, []);

    const loadModules = async () => {
        // Ensuring we select the correct columns. Check if 'titulo' exists or needs mapping.
        // Based on user prompt: id, titulo, descricao, is_degustacao
        const { data, error } = await supabase
            .from('modulos')
            .select('id, titulo, ordem, forca, descricao, is_degustacao')
            // .eq('forca', 'marinha') // SECURITY: Hardcoded force for now (DISABLED FOR DEBUG)
            .order('ordem');

        console.log('MODULOS:', { data, error });

        if (error) {
            console.error('Error fetching modules:', error);
        }

        console.log('RESPOSTA BANCO (Modulos):', { data, error });

        if (!error && data) {
            setModules(data);
        }

        setLoading(false);
    };

    if (loading || !profile) {
        return (
            <View style={[styles.safe, { justifyContent: 'center', alignItems: 'center' }]}>
                <ActivityIndicator color={theme.colors.gold} />
            </View>
        );
    }

    // 🔑 FILTRO SILENCIOSO
    const visibleModules = modules.filter((modulo) =>
        canAccessModule({ profile, modulo })
    );

    return (
        <SafeAreaView style={styles.safe}>
            <FlatList
                data={visibleModules}
                keyExtractor={(item) => item.id}
                contentContainerStyle={styles.list}
                renderItem={({ item }) => (
                    <TouchableOpacity
                        style={styles.card}
                        onPress={() => router.push({
                            pathname: `/modulo/${item.id}`,
                            params: {
                                moduloTitulo: item.titulo,
                                isDegustacao: String(item.is_degustacao)
                            }
                        })}
                    >
                        <Text style={styles.title}>{item.titulo}</Text>
                        <Text style={styles.description}>
                            {item.descricao}
                        </Text>
                    </TouchableOpacity>
                )}
            />
        </SafeAreaView>
    );
}

const styles = StyleSheet.create({
    safe: {
        flex: 1,
        backgroundColor: theme.colors.background,
    },
    list: {
        padding: 16,
        gap: 16,
    },
    card: {
        backgroundColor: theme.colors.surface,
        borderRadius: 14,
        padding: 20,
        borderLeftWidth: 4,
        borderLeftColor: theme.colors.gold,
        elevation: 2,
    },
    title: {
        color: theme.colors.gold,
        fontSize: 18,
        fontWeight: '600',
        marginBottom: 6,
        textTransform: 'uppercase',
    },
    description: {
        color: theme.colors.textSecondary,
        fontSize: 14,
        lineHeight: 20,
    },
});
