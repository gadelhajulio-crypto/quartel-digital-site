import { View, StyleSheet } from 'react-native';
import { Video } from 'expo-av';
import { useForceTheme } from '../../context/ForceThemeContext';

interface ReviewVideoPlayerProps {
    sourceUrl: string;
}

export function ReviewVideoPlayer({ sourceUrl }: ReviewVideoPlayerProps) {
    const { theme } = useForceTheme();

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
            <Video
                source={{ uri: sourceUrl }}
                style={styles.video}
                useNativeControls
                resizeMode="contain"
                shouldPlay={false}
            />
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        borderRadius: 10,
        borderWidth: 1,
        overflow: 'hidden',
    },
    video: {
        width: '100%',
        height: 220,
        backgroundColor: '#000',
    },
});
