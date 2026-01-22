import React from 'react';
import { View, Text, Image, StyleSheet, TouchableOpacity } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useRouter } from 'expo-router';
import { useAuth } from '../../../src/context/AuthContext';
import { supabase } from '../../../src/lib/supabase';

// Mapeamento Seguro (Cópia da lógica do Chat)
const INSTRUCTOR_ASSETS = {
    objetivo: {
        name: 'Instrutor Rocha',
        avatar: require('../../../assets/instructors/marinha/objetivo/instrutor-objetivo-marinha-avatar.png'),
    },
    estrategico: {
        name: 'Instrutor Azevedo',
        avatar: require('../../../assets/instructors/marinha/estrategico/instrutor-estrategico-marinha-avatar.png'),
    },
    didatico: {
        // Pasta 'didatica', arquivo 'instrutor'
        name: 'Instrutora Helena',
        avatar: require('../../../assets/instructors/marinha/didatica/instrutor-didatica-marinha-avatar.png'),
    },
};

export default function ProfileScreen() {
    const { user, profile, signOut } = useAuth();
    const router = useRouter();

    const currentInstructorId = profile?.instructor_profile_id || 'objetivo';
    const instructorData = INSTRUCTOR_ASSETS[currentInstructorId as keyof typeof INSTRUCTOR_ASSETS] || INSTRUCTOR_ASSETS.objetivo;

    const handleLogout = async () => {
        await signOut();
    };

    return (
        <View style={styles.container}>
            <SafeAreaView style={styles.content}>
                <Text style={styles.title}>Perfil do Recruta</Text>
                <Text style={styles.email}>{user?.email}</Text>

                <View style={styles.instructorCard}>
                    <Text style={styles.label}>Instrutor Atual</Text>
                    <View style={styles.instructorRow}>
                        <Image source={instructorData.avatar} style={styles.avatar} />
                        <Text style={styles.instructorName}>{instructorData.name}</Text>
                    </View>

                    <TouchableOpacity
                        style={styles.changeButton}
                        onPress={() => router.push('/(onboarding)/instructor-select?mode=change')}
                    >
                        <Text style={styles.changeButtonText}>Trocar Instrutor</Text>
                    </TouchableOpacity>
                </View>

                <TouchableOpacity style={styles.logoutButton} onPress={handleLogout}>
                    <Text style={styles.logoutText}>Sair do Quartel</Text>
                </TouchableOpacity>
            </SafeAreaView>
        </View>
    );
}

const styles = StyleSheet.create({
    container: { flex: 1, backgroundColor: '#0F172A' },
    content: { padding: 24 },
    title: { color: '#F8FAFC', fontSize: 24, fontWeight: 'bold', marginBottom: 8 },
    email: { color: '#94A3B8', fontSize: 16, marginBottom: 32 },
    instructorCard: { backgroundColor: '#1E293B', padding: 20, borderRadius: 16, marginBottom: 24, borderWidth: 1, borderColor: '#334155' },
    label: { color: '#64748B', fontSize: 12, fontWeight: 'bold', textTransform: 'uppercase', marginBottom: 12 },
    instructorRow: { flexDirection: 'row', alignItems: 'center', marginBottom: 20 },
    avatar: { width: 50, height: 50, borderRadius: 25, marginRight: 16, backgroundColor: '#334155' },
    instructorName: { color: '#F8FAFC', fontSize: 18, fontWeight: 'bold' },
    changeButton: { backgroundColor: 'transparent', borderWidth: 1, borderColor: '#38BDF8', padding: 12, borderRadius: 8, alignItems: 'center' },
    changeButtonText: { color: '#38BDF8', fontWeight: 'bold' },
    logoutButton: { padding: 16, alignItems: 'center' },
    logoutText: { color: '#EF4444', fontWeight: 'bold' },
});
