import { Tabs } from 'expo-router';
import React from 'react';
import BottomBar from '../../src/components/navigation/BottomBar';

export default function TabsLayout() {
    return (
        <Tabs
            screenOptions={{
                headerShown: false,
            }}
            tabBar={(props) => <BottomBar />}
        >
            <Tabs.Screen name="index" options={{ href: null }} />
            <Tabs.Screen name="modules" options={{ href: null }} />
            <Tabs.Screen name="history" options={{ href: null }} />
            <Tabs.Screen name="messages" options={{ href: null }} />
            <Tabs.Screen name="settings" options={{ href: null }} />
            <Tabs.Screen name="ranking" options={{ href: null }} />
            <Tabs.Screen name="profile" options={{ href: null }} />
            <Tabs.Screen name="progress" options={{ href: null }} />
            <Tabs.Screen name="reviews" options={{ href: null }} />
            <Tabs.Screen name="notices" options={{ href: null }} />
            <Tabs.Screen name="chat" options={{ href: null }} />
        </Tabs>
    );
}
