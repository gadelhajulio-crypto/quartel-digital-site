import React, { useEffect, useRef } from 'react';
import { View, Text, StyleSheet, Animated } from 'react-native';
import { theme } from '../theme';

type XpToastProps = {
    visible: boolean;
    amount: number;
    message: string;
    onHide: () => void;
    color?: string;
};

export function XpToast({ visible, amount, message, onHide, color = theme.colors.gold }: XpToastProps) {
    const fadeAnim = useRef(new Animated.Value(0)).current;
    const translateY = useRef(new Animated.Value(-20)).current;

    useEffect(() => {
        if (visible) {
            Animated.parallel([
                Animated.timing(fadeAnim, { toValue: 1, duration: 500, useNativeDriver: true }),
                Animated.timing(translateY, { toValue: 0, duration: 500, useNativeDriver: true }),
            ]).start();

            const timer = setTimeout(() => {
                Animated.parallel([
                    Animated.timing(fadeAnim, { toValue: 0, duration: 500, useNativeDriver: true }),
                    Animated.timing(translateY, { toValue: -20, duration: 500, useNativeDriver: true }),
                ]).start(() => onHide());
            }, 3000);

            return () => clearTimeout(timer);
        }
    }, [visible]);

    if (!visible) return null;

    return (
        <Animated.View
            style={[
                styles.container,
                {
                    opacity: fadeAnim,
                    transform: [{ translateY }],
                    borderColor: color,
                    shadowColor: color
                }
            ]}
        >
            <Text style={[styles.xpText, { color: color }]}>+{amount} XP</Text>
            <Text style={styles.messageText}>{message}</Text>
        </Animated.View>
    );
}

const styles = StyleSheet.create({
    container: {
        position: 'absolute',
        top: 60,
        alignSelf: 'center',
        backgroundColor: 'rgba(0,0,0,0.9)',
        paddingHorizontal: 20,
        paddingVertical: 12,
        borderRadius: 30,
        borderWidth: 1,
        flexDirection: 'row',
        alignItems: 'center',
        zIndex: 100,
        shadowOffset: { width: 0, height: 4 },
        shadowOpacity: 0.5,
        shadowRadius: 10,
        elevation: 10,
    },
    xpText: {
        fontWeight: 'bold',
        fontSize: 16,
        marginRight: 10,
    },
    messageText: {
        color: '#FFF',
        fontSize: 14,
        fontWeight: '600',
    }
});
