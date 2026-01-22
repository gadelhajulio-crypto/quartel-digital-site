import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { useState } from 'react';
import { useRouter } from 'expo-router';
import { useForceTheme } from '../../../src/context/ForceThemeContext';
import { supabase } from '../../../src/lib/supabase';
import { useAuth } from '../../../src/context/AuthContext';

const INSTRUCTORS = [
    {
        id: 'objetivo',
        nome: 'Instrutor Objetivo',
        descricao: 'Direto, disciplinado e focado em progresso.',
    },
    {
        id: 'estrategico',
        nome: 'Instrutor Estratégico',
        descricao: 'Analítico, explica o porquê das regras.',
    },
    {
        id: 'didatico',
        nome: 'Instrutora Didática',
        descricao: 'Clara, paciente e focada no aprendizado.',
    },
];

export default function SelectInstructorScreen() {
    const { theme } = useForceTheme();
    const { user } = useAuth();
    const router = useRouter();
    const [selected, setSelected] = useState<string | null>(null);
    const [loading, setLoading] = useState(false);

    async function handleConfirm() {
        if (!selected || !user) return;
        setLoading(true);

        // 🔒 salvar no backend
        const { error } = await supabase
            .from('profiles')
            .update({ instructor_profile_id: selected })
            .eq('id', user.id);

        if (error) {
            console.error('Erro ao salvar instrutor:', error);
            setLoading(false);
            return;
        }

        console.log('Instrutor escolhido:', selected);
        router.replace('/(app)/instrutor');
    }

    return (
        <View style={styles.container}>
            <Text style={styles.title}>Escolha seu instrutor</Text>
            <Text style={styles.subtitle}>
                Este instrutor irá orientar você durante toda a jornada.
            </Text>

            {INSTRUCTORS.map((inst) => {
                const active = selected === inst.id;

                return (
                    <TouchableOpacity
                        key={inst.id}
                        style={[
                            styles.card,
                            active && {
                                borderColor: theme.accent, // Using theme.accent (gold)
                                borderWidth: 2,
                            },
                        ]}
                        onPress={() => setSelected(inst.id)}
                    >
                        <Text style={[styles.cardTitle, { color: theme.textPrimary }]}>{inst.nome}</Text>
                        <Text style={styles.cardDesc}>{inst.descricao}</Text>
                    </TouchableOpacity>
                );
            })}

            <TouchableOpacity
                style={[
                    styles.confirm,
                    {
                        backgroundColor: selected ? theme.accent : '#3A3D42',
                    },
                ]}
                disabled={!selected || loading}
                onPress={handleConfirm}
            >
                <Text style={[styles.confirmText, { color: selected ? '#000' : '#FFFFFF' }]}>
                    {loading ? 'Salvando...' : 'Confirmar escolha'}
                </Text>
            </TouchableOpacity>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#0E0F12',
        padding: 20,
        justifyContent: 'center', // Center vertically for better look
    },
    title: {
        color: '#FFFFFF',
        fontSize: 22,
        fontWeight: 'bold',
        marginBottom: 8,
        textAlign: 'center',
    },
    subtitle: {
        color: '#A0A3A8',
        fontSize: 14,
        marginBottom: 32,
        textAlign: 'center',
    },
    card: {
        backgroundColor: '#15171C',
        borderRadius: 12,
        padding: 16,
        marginBottom: 12,
        borderWidth: 1,
        borderColor: '#1C1F26',
    },
    cardTitle: {
        fontSize: 16,
        fontWeight: '600',
        marginBottom: 4,
    },
    cardDesc: {
        color: '#A0A3A8',
        fontSize: 13,
    },
    confirm: {
        marginTop: 24,
        padding: 16,
        borderRadius: 10,
        alignItems: 'center',
    },
    confirmText: {
        fontWeight: 'bold',
        fontSize: 16,
        textTransform: 'uppercase',
    },
});
