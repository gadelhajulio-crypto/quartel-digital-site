import React, { useState, useEffect } from 'react';
import {
    View,
    Text,
    StyleSheet,
    ScrollView,
    TouchableOpacity,
    ActivityIndicator
} from 'react-native';
import { Audio, Video, ResizeMode } from 'expo-av';
import { useForceTheme } from '../context/ForceThemeContext';
import { Ionicons } from '@expo/vector-icons';

type Props = {
    revisao: {
        titulo: string;
        audio_url?: string;
        video_url?: string;
        descricao?: string; // Optional text
    }
};

export default function ReviewScreen({ revisao }: Props) {
    const { titulo, audio_url, video_url } = revisao;
    const { theme } = useForceTheme(); // Dynamic Theme
    const styles = getStyles(theme);

    // Pass theme to AudioPlayer via props or let it hook vertically? 
    // It's a component in same file, can use hook too.

    return (
        <ScrollView style={styles.container} contentContainerStyle={{ paddingBottom: 40 }}>
            <Text style={styles.title}>{titulo}</Text>

            {/* Optional Video */}
            {video_url && (
                <View style={styles.videoWrapper}>
                    <Video
                        source={{ uri: video_url }}
                        useNativeControls
                        resizeMode={ResizeMode.CONTAIN}
                        style={styles.video}
                    />
                </View>
            )}

            {/* Main Audio Player */}
            {audio_url && <AudioPlayer audioUrl={audio_url} />}

            <Text style={styles.text}>
                Utilize este material como reforço dos conceitos
                essenciais apresentados no módulo.
            </Text>
        </ScrollView>
    );
}

function AudioPlayer({ audioUrl }: { audioUrl: string }) {
    const [sound, setSound] = useState<Audio.Sound | null>(null);
    const [isPlaying, setIsPlaying] = useState(false);
    const [loading, setLoading] = useState(false);

    const { theme } = useForceTheme();
    const styles = getStyles(theme);

    useEffect(() => {
        return () => {
            if (sound) {
                sound.unloadAsync();
            }
        };
    }, [sound]);

    const playAudio = async () => {
        try {
            if (sound) {
                if (isPlaying) {
                    await sound.pauseAsync();
                    setIsPlaying(false);
                } else {
                    await sound.playAsync();
                    setIsPlaying(true);
                }
                return;
            }

            setLoading(true);
            const { sound: newSound } = await Audio.Sound.createAsync(
                { uri: audioUrl },
                { shouldPlay: true }
            );
            newSound.setOnPlaybackStatusUpdate((status) => {
                if (status.isLoaded) {
                    setIsPlaying(status.isPlaying);
                    if (status.didJustFinish) {
                        setIsPlaying(false);
                        newSound.setPositionAsync(0); // Reset
                    }
                }
            });
            setSound(newSound);
        } catch (error) {
            console.error('Error playing audio', error);
        } finally {
            setLoading(false);
        }
    };

    return (
        <View style={styles.audioBox}>
            <TouchableOpacity onPress={playAudio} style={styles.playButton} disabled={loading}>
                {loading ? (
                    <ActivityIndicator color={theme.accent} />
                ) : (
                    <Ionicons name={isPlaying ? "pause-circle" : "play-circle"} size={48} color={theme.accent} />
                )}
                <Text style={styles.playText}>
                    {isPlaying ? "PAUSAR REVISÃO" : "REPRODUZIR ÁUDIO DE REVISÃO"}
                </Text>
            </TouchableOpacity>
        </View>
    );
}

const getStyles = (theme: any) => StyleSheet.create({
    container: {
        flex: 1,
        padding: 20,
        backgroundColor: theme.background,
    },
    title: {
        fontSize: 22,
        fontWeight: 'bold',
        color: theme.accent || '#FFD166',
        marginBottom: 20,
        textTransform: 'uppercase',
    },
    videoWrapper: {
        width: '100%',
        aspectRatio: 16 / 9,
        backgroundColor: '#000',
        marginBottom: 20,
        borderRadius: 8,
        overflow: 'hidden',
    },
    video: {
        flex: 1,
    },
    audioBox: {
        padding: 20,
        backgroundColor: theme.card,
        borderRadius: 12,
        marginBottom: 20,
        alignItems: 'center',
        borderWidth: 1,
        borderColor: theme.accent || '#FFD166',
    },
    playButton: {
        alignItems: 'center',
        gap: 10,
    },
    playText: {
        color: theme.textPrimary,
        fontWeight: 'bold',
        fontSize: 14,
        textTransform: 'uppercase',
        letterSpacing: 1,
    },
    text: {
        color: theme.textSecondary,
        fontSize: 14,
        lineHeight: 22,
        textAlign: 'center',
    },
});
