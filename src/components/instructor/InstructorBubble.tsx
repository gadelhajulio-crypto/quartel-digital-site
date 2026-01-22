import React from 'react';
import { View, Text, StyleSheet } from 'react-native';

export default function InstructorBubble({ text }: { text: string }) {
    return (
        <View style={styles.wrapper}>
            <View style={styles.bubble}>
                <Text style={styles.text}>{text}</Text>
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    wrapper: {
        alignItems: 'flex-start',
        marginVertical: 6,
        marginLeft: 16, // Add some margin for better spacing
    },
    bubble: {
        backgroundColor: '#1C1F26',
        padding: 12,
        borderRadius: 10,
        borderLeftWidth: 3,
        borderLeftColor: '#C9A24D',
        maxWidth: '85%',
    },
    text: {
        color: '#FFFFFF',
        fontSize: 14,
    },
});
