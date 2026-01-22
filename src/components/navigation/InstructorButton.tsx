import React from 'react';
import { TouchableOpacity, StyleSheet, Image, View } from 'react-native';
import { useRouter } from 'expo-router';
import { useBottomBarState } from '../../hooks/useBottomBarState';
import { useForceTheme } from '../../context/ForceThemeContext';
import { useAuth } from '../../context/AuthContext';
import { INSTRUCTOR_AVATARS } from '../../constants/instructorAvatars';

export default function InstructorButton() {
    const router = useRouter();
    const { isInstructor } = useBottomBarState();
    const { theme } = useForceTheme();
    const { profile } = useAuth();

    // Fallback seguro se não tiver instrutor ou asset não encontrado
    const avatarSource = INSTRUCTOR_AVATARS[profile?.instructor_profile_id as keyof typeof INSTRUCTOR_AVATARS] || INSTRUCTOR_AVATARS.objetivo;

    if (!profile?.instructor_profile_id) return null; // Não renderiza sem instrutor selecionado (regra de UI)

    return (
        <TouchableOpacity
            style={[
                styles.button,
                {
                    backgroundColor: theme.card, // Fundo neutro para a imagem
                    elevation: isInstructor ? 8 : 4,
                    borderWidth: 2,
                    borderColor: theme.accent, // Borda na cor da força
                    zIndex: 10,
                },
            ]}
            onPress={() => router.push('/chat')}
            activeOpacity={0.85}
        >
            <Image
                source={avatarSource}
                style={styles.avatar}
                resizeMode="cover"
            />
            {/* Indicador Online */}
            <View style={[styles.onlineIndicator, { borderColor: theme.card }]} />
        </TouchableOpacity>
    );
}

const styles = StyleSheet.create({
    button: {
        width: 64,
        height: 64,
        borderRadius: 32,
        alignItems: 'center',
        justifyContent: 'center',
        marginTop: -24, // Lift it up
        shadowColor: '#000',
        shadowOffset: { width: 0, height: 4 },
        shadowOpacity: 0.3,
        shadowRadius: 4,
        position: 'relative', // Para o indicador absoluto
    },
    avatar: {
        width: '100%',
        height: '100%',
        borderRadius: 32,
    },
    onlineIndicator: {
        position: 'absolute',
        bottom: 2,
        right: 2,
        width: 14,
        height: 14,
        borderRadius: 7,
        backgroundColor: '#4ADE80', // Green-400
        borderWidth: 2,
    }
});
