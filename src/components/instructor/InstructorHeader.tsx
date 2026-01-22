import React from 'react';
import { View, Text, StyleSheet } from 'react-native';

export default function InstructorHeader() {
    return (
        <View style={styles.container}>
            <Text style={styles.title}>Instrutor Virtual</Text>
            <Text style={styles.subtitle}>Quartel Digital</Text>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        padding: 16,
        borderBottomWidth: 1,
        borderBottomColor: '#1C1F26',
        backgroundColor: '#0E0F12',
    },
    title: {
        color: '#C9A24D',
        fontSize: 16,
        fontWeight: '600',
    },
    subtitle: {
        color: '#A0A3A8',
        fontSize: 12,
    },
});
