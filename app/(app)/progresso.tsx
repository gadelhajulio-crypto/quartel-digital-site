import React from 'react';
import { View, Text, StyleSheet } from "react-native";
import { useForceTheme } from "../../src/context/ForceThemeContext";
import { Header } from "../../src/components/Header";
import { ProgressCard } from "../../src/components/ProgressCard";

export default function Progresso() {
    const { theme } = useForceTheme(); // Dynamic Theme
    const styles = getStyles(theme);

    return (
        <View style={styles.container}>
            <Header title="SEU PROGRESSO" />
            <ProgressCard />
            <View style={{ marginTop: 20 }}>
                <Text style={{ color: theme.textSecondary, textAlign: 'center' }}>Estatísticas Detalhadas em Breve.</Text>
            </View>
        </View>
    );
}

const getStyles = (theme: any) => StyleSheet.create({
    container: {
        backgroundColor: theme.background,
        flex: 1,
        padding: 16,
    },
});
