import React from 'react';
import { Pressable, Text, StyleSheet } from "react-native";
import { theme } from "../theme";

export function ActionCard({ title, onPress }: { title: string, onPress: () => void }) {
    return (
        <Pressable style={styles.card} onPress={onPress}>
            <Text style={styles.text}>{title}</Text>
        </Pressable>
    );
}

const styles = StyleSheet.create({
    card: {
        backgroundColor: theme.colors.cardSecondary,
        borderRadius: 14,
        height: 120,
        width: "48%",
        justifyContent: "center",
        alignItems: "center",
    },
    text: {
        color: theme.colors.textPrimary,
        fontSize: 15,
        fontWeight: "600",
    },
});
