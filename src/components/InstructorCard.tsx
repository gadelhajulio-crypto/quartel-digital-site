import React from 'react';
import { Text, Image, StyleSheet, Dimensions } from 'react-native';
import Animated, {
    interpolate,
    useAnimatedStyle,
    Extrapolate,
    SharedValue,
} from 'react-native-reanimated';
import { useForceTheme } from '../context/ForceThemeContext';

const { width } = Dimensions.get('window');
const CARD_WIDTH = width * 0.78;

interface Props {
    index: number;
    scrollX: SharedValue<number>;
    name: string;
    description: string;
    image: any;
}

export function InstructorCard({
    index,
    scrollX,
    name,
    description,
    image,
}: Props) {
    const { theme } = useForceTheme();

    const animatedStyle = useAnimatedStyle(() => {
        const inputRange = [
            (index - 1) * CARD_WIDTH,
            index * CARD_WIDTH,
            (index + 1) * CARD_WIDTH,
        ];

        const scale = interpolate(
            scrollX.value,
            inputRange,
            [0.9, 1, 0.9],
            Extrapolate.CLAMP
        );

        const opacity = interpolate(
            scrollX.value,
            inputRange,
            [0.6, 1, 0.6],
            Extrapolate.CLAMP
        );

        return {
            transform: [{ scale }],
            opacity,
        };
    });

    return (
        <Animated.View style={[styles.card, animatedStyle]}>
            <Image source={image} style={styles.image} />

            <Text style={[styles.name, { color: theme.textPrimary }]}>{name}</Text>
            <Text style={[styles.description, { color: theme.textSecondary }]}>{description}</Text>
        </Animated.View>
    );
}

const styles = StyleSheet.create({
    card: {
        width: CARD_WIDTH,
        marginHorizontal: 10,
        borderRadius: 18,
        backgroundColor: '#0E1621',
        padding: 16,
        alignItems: 'center',
    },
    image: {
        width: '100%',
        height: 260,
        resizeMode: 'contain',
        marginBottom: 16,
        borderRadius: 8,
    },
    name: {
        fontSize: 20,
        fontWeight: '700',
        textAlign: 'center',
        marginBottom: 8,
    },
    description: {
        fontSize: 14,
        lineHeight: 20,
        textAlign: 'center',
    },
});
