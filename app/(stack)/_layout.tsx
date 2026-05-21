import { Stack } from 'expo-router';
import React from 'react';

export default function StackLayout() {
    return (
        <Stack
            screenOptions={{
                headerShown: true,
                headerBackTitle: '',
            }}
        >
            {/* Seletor de instrutor usa header institucional próprio */}
            <Stack.Screen name="instructor/select" options={{ headerShown: false }} />
            {/* Lista institucional de conversas usa header institucional próprio */}
            <Stack.Screen name="conversations/index" options={{ headerShown: false }} />
        </Stack>
    );
}
