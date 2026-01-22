import React from 'react';
import { View, Text, StyleSheet } from "react-native";
import { theme } from "../theme";
import { AnimatedCircularProgress } from "react-native-circular-progress";

export function ProgressCard() {
    return (
        <View style={styles.card}>
            <AnimatedCircularProgress
                size={100}
                width={8}
                fill={72}
                tintColor={theme.colors.gold}
                backgroundColor={theme.colors.muted}
                lineCap="round"
            >
                {() => (
                    <Text style={styles.percent}>72%</Text>
                )}
            </AnimatedCircularProgress>
            <Text style={styles.label}>Progresso Geral</Text>
        </View>
    );
}

const styles = StyleSheet.create({
    card: {
        backgroundColor: theme.colors.card,
        borderRadius: 16,
        height: 180,
        justifyContent: "center",
        alignItems: "center",
        marginBottom: 16,
    },
    percent: {
        color: theme.colors.textPrimary,
        fontSize: 18,
        fontWeight: "700",
    },
    label: {
        marginTop: 8,
        color: theme.colors.textSecondary,
        fontSize: 12,
    },
});
