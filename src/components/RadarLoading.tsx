import React, { useEffect, useRef } from 'react';
import { View, StyleSheet, Animated, Easing } from 'react-native';
import { theme } from '../theme';

type RadarLoadingProps = {
    color?: string;
};

export function RadarLoading({ color = theme.colors.oliveGreen }: RadarLoadingProps) {
    const spinValue = useRef(new Animated.Value(0)).current;
    const pulseValue = useRef(new Animated.Value(1)).current;

    useEffect(() => {
        // Animação de Rotação (Varredura)
        Animated.loop(
            Animated.timing(spinValue, {
                toValue: 1,
                duration: 2000,
                easing: Easing.linear,
                useNativeDriver: true,
            })
        ).start();

        // Animação de Pulso (Opacidade)
        Animated.loop(
            Animated.sequence([
                Animated.timing(pulseValue, {
                    toValue: 0.4,
                    duration: 1000,
                    useNativeDriver: true,
                }),
                Animated.timing(pulseValue, {
                    toValue: 1,
                    duration: 1000,
                    useNativeDriver: true,
                }),
            ])
        ).start();
    }, []);

    const spin = spinValue.interpolate({
        inputRange: [0, 1],
        outputRange: ['0deg', '360deg'],
    });

    return (
        <View style={styles.container}>
            <View style={styles.radarContainer}>
                {/* Círculos Concêntricos */}
                <View style={[styles.circle, styles.outerCircle, { borderColor: color }]} />
                <View style={[styles.circle, styles.innerCircle, { borderColor: color }]} />

                {/* Varredura do Radar */}
                <Animated.View
                    style={[
                        styles.sweep,
                        {
                            transform: [{ rotate: spin }],
                            borderRightColor: theme.colors.gold // Mantém dourado ou pode ser 'color'
                        }
                    ]}
                />

                {/* Ponto Central Pulsante */}
                <Animated.View
                    style={[
                        styles.dot,
                        {
                            opacity: pulseValue,
                            backgroundColor: theme.colors.gold
                        }
                    ]}
                />
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        padding: theme.spacing.m,
        alignItems: 'center',
        justifyContent: 'center',
    },
    radarContainer: {
        width: 40,
        height: 40,
        alignItems: 'center',
        justifyContent: 'center',
        position: 'relative',
    },
    circle: {
        position: 'absolute',
        borderRadius: 20,
        borderWidth: 1,
    },
    outerCircle: {
        width: 40,
        height: 40,
        opacity: 0.5,
    },
    innerCircle: {
        width: 20,
        height: 20,
        opacity: 0.8,
    },
    sweep: {
        position: 'absolute',
        width: 20,
        height: 20,
        borderRightWidth: 1,
        borderBottomWidth: 1,
        borderColor: 'transparent',
        top: 0,
        left: 0,
        borderRadius: 20,
        opacity: 0.8,
    },
    dot: {
        width: 6,
        height: 6,
        borderRadius: 3,
    },
});
