import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Image } from 'react-native';
import { useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { useForceTheme } from '../../context/ForceThemeContext';
import { useAuth } from '../../context/AuthContext';

export default function RecruitHeader() {
    const { theme } = useForceTheme();
    const { profile } = useAuth();
    const router = useRouter();

    const forceName = profile?.forca ? profile.forca.toUpperCase() : 'FORÇA NÃO DEFINIDA';
    const rankName = profile?.patente ? profile.patente.toUpperCase() : 'RECRUTA ZERO';

    return (
        <View style={styles.container}>
            <View>
                <Text style={[styles.force, { color: theme.textSecondary }]}>
                    {forceName}
                </Text>
                <Text style={[styles.name, { color: theme.textPrimary }]}>
                    {profile?.nome ? profile.nome.toUpperCase() : 'RECRUTA'}
                </Text>
                <View style={styles.rankContainer}>
                    <Ionicons name="medal" size={14} color={theme.accent} />
                    <Text style={[styles.rank, { color: theme.accent }]}>
                        {rankName}
                    </Text>
                </View>
            </View>

            <TouchableOpacity onPress={() => router.push('/perfil')}>
                <View style={[styles.avatarBorder, { borderColor: theme.accent, backgroundColor: theme.card }]}>
                    {profile?.avatar_url ? (
                        <Image source={{ uri: profile.avatar_url }} style={styles.avatar} />
                    ) : (
                        <Ionicons name="person" size={24} color={theme.accent} />
                    )}
                </View>
            </TouchableOpacity>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'flex-start',
        marginBottom: 24,
        marginTop: 10,
    },
    force: {
        fontSize: 10,
        fontWeight: 'bold',
        letterSpacing: 2,
        marginBottom: 4,
        opacity: 0.7,
    },
    name: {
        fontSize: 24,
        fontWeight: 'bold',
        textTransform: 'uppercase',
        marginBottom: 8,
    },
    rankContainer: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 6,
        backgroundColor: 'rgba(255,255,255,0.05)',
        alignSelf: 'flex-start',
        paddingHorizontal: 8,
        paddingVertical: 4,
        borderRadius: 4,
    },
    rank: {
        fontSize: 12,
        fontWeight: 'bold',
        letterSpacing: 1,
    },
    avatarBorder: {
        width: 48,
        height: 48,
        borderRadius: 24,
        borderWidth: 2,
        justifyContent: 'center',
        alignItems: 'center',
        overflow: 'hidden',
    },
    avatar: {
        width: '100%',
        height: '100%',
    }
});
