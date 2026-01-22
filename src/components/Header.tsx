import React from 'react';
import { View, Text, StyleSheet } from "react-native";
import { useForceTheme } from "../context/ForceThemeContext";

export function Header({ title, subtitle, rightAction }: { title: string, subtitle?: string, rightAction?: React.ReactNode }) {
    const { theme } = useForceTheme();
    const styles = getStyles(theme);

    return (
        <View style={styles.container}>
            <View style={{ flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' }}>
                <View>
                    <Text style={styles.title}>{title}</Text>
                    {subtitle && <Text style={styles.subtitle}>{subtitle}</Text>}
                </View>
                {rightAction}
            </View>
        </View>
    );
}

const getStyles = (theme: any) => StyleSheet.create({
    container: { marginBottom: 16 },
    title: {
        color: theme.textPrimary,
        fontSize: 22,
        fontWeight: "700",
    },
    subtitle: {
        color: theme.textSecondary,
        fontSize: 14,
        marginTop: 4,
    },
});
