import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { useEffect, useRef, useState } from 'react';
import { Audio } from 'expo-av';
import { Ionicons } from '@expo/vector-icons';
import { useForceTheme } from '../../context/ForceThemeContext';

interface ReviewAudioPlayerProps {
    sourceUrl: string;
}

export function ReviewAudioPlayer({ sourceUrl }: ReviewAudioPlayerProps) {
    const { theme } = useForceTheme();
    const soundRef = useRef<Audio.Sound | null>(null);
    const [playing, setPlaying] = useState(false);

    useEffect(() => {
        let mounted = true;

        async function load() {
            const { sound } = await Audio.Sound.createAsync(
                { uri: sourceUrl },
                { shouldPlay: false }
            );

            if (mounted) {
                soundRef.current = sound;
            }
        }

        load();

        return () => {
            mounted = false;
            if (soundRef.current) {
                soundRef.current.unloadAsync();
                soundRef.current = null;
            }
        };
    }, [sourceUrl]);

    const toggle = async () => {
        if (!soundRef.current) return;

        if (playing) {
            await soundRef.current.pauseAsync();
            setPlaying(false);
        } else {
            await soundRef.current.playAsync();
            setPlaying(true);
        }
    };

    return (
        <View
            style={[
                styles.container,
                {
                    backgroundColor: theme.card,
                    borderColor: theme.border,
                },
            ]}
        >
            <TouchableOpacity onPress={toggle} style={styles.button}>
                <Ionicons
                    name={playing ? 'pause' : 'play'}
                    size={28}
                    color={theme.primary}
                />
            </TouchableOpacity>

            <Text style={[styles.label, { color: theme.text }]}>
                Revisão em Áudio
            </Text>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        padding: 20,
        borderRadius: 10,
        borderWidth: 1,
        alignItems: 'center',
    },
    button: {
        marginBottom: 12,
    },
    label: {
        fontSize: 15,
        fontWeight: '500',
    },
});
