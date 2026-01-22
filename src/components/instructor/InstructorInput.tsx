import React, { useState } from 'react';
import { View, TextInput, TouchableOpacity, StyleSheet } from 'react-native';
import { Ionicons } from '@expo/vector-icons';

export default function InstructorInput({
    onSend,
}: {
    onSend: (text: string) => void;
}) {
    const [text, setText] = useState('');

    function handlePress() {
        onSend(text);
        setText('');
    }

    return (
        <View style={styles.container}>
            <TextInput
                value={text}
                onChangeText={setText}
                placeholder="Digite sua pergunta…"
                placeholderTextColor="#6B6E73"
                style={styles.input}
                returnKeyType="send"
                onSubmitEditing={handlePress}
            />

            <TouchableOpacity onPress={handlePress}>
                <Ionicons name="send" size={22} color="#C9A24D" />
            </TouchableOpacity>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flexDirection: 'row',
        alignItems: 'center',
        padding: 12,
        borderTopWidth: 1,
        borderTopColor: '#1C1F26',
        backgroundColor: '#0E0F12',
    },
    input: {
        flex: 1,
        color: '#FFFFFF',
        marginRight: 12,
        fontSize: 14,
        paddingVertical: 8, // Improve touch area
    },
});
