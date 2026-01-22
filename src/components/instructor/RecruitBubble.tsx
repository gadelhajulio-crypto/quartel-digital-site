import React from 'react';
import { View, Text, StyleSheet } from 'react-native';

export default function RecruitBubble({
    text,
    color,
}: {
    text: string;
    color: string;
}) {
    return (
        <View style={styles.wrapper}>
            <View style={[styles.bubble, { backgroundColor: color }]}>
                <Text style={styles.text}>{text}</Text>
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    wrapper: {
        alignItems: 'flex-end',
        marginVertical: 6,
        marginRight: 16, // Add some margin
    },
    bubble: {
        padding: 12,
        borderRadius: 10,
        maxWidth: '85%',
    },
    text: {
        color: '#FFFFFF',
        fontSize: 14,
    },
});
