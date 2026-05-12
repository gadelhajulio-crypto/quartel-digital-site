import React from 'react';
import { View, Text, ActivityIndicator, StyleSheet, SafeAreaView } from 'react-native';
import { colors } from '../../theme';

export function AuthLoadingScreen() {
    return (
        <SafeAreaView style={styles.safe}>
            <View style={styles.container}>
                <ActivityIndicator size="large" color={colors.gold} />
                <Text style={styles.text}>Validando acesso institucional...</Text>
            </View>
        </SafeAreaView>
    );
}

const styles = StyleSheet.create({
    safe: {
        flex: 1,
        backgroundColor: colors.background,
    },
    container: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
        gap: 16,
    },
    text: {
        color: colors.textSecondary,
        fontSize: 16,
        fontWeight: '500',
    },
});
