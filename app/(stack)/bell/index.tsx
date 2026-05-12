import React from 'react';
import { View, StyleSheet, ScrollView } from 'react-native';
import { useForceTheme } from '../../../src/context/ForceThemeContext';
import { SinoDeBordo } from '../../../src/components/SinoDeBordo';

export default function SinoScreen() {
    const { theme } = useForceTheme(); // Dynamic Theme
    const styles = getStyles(theme);

    return (
        <View style={styles.container}>
            <ScrollView contentContainerStyle={styles.content}>
                <SinoDeBordo />
            </ScrollView>
        </View>
    );
}

const getStyles = (theme: any) => StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: theme.background,
    },
    content: {
        padding: 16, // Was theme.spacing.m (assumed 16)
    },
});
