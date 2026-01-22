import React from 'react';
import { View, TouchableOpacity, StyleSheet, Platform } from 'react-native';
import { useRouter, usePathname } from 'expo-router'; // usePathname for active state
import { useBottomBarState } from '../../hooks/useBottomBarState';
import PanelIcon from './PanelIcon';
// Removed ProfileIcon
import ContinuarIcon from './ContinuarIcon'; // New Icon
import InstructorButton from './InstructorButton';
import { useForceTheme } from '../../context/ForceThemeContext';

export default function BottomBar() {
    const router = useRouter();
    const pathname = usePathname();
    const { isPanel } = useBottomBarState(); // Keeping existing logic where possible
    const { theme } = useForceTheme();

    const isContinuar = pathname.includes('/continuar');

    return (
        <View style={[styles.container, { backgroundColor: theme.card, borderTopColor: 'rgba(255,255,255,0.1)' }]}>
            {/* PAINEL - Left */}
            <TouchableOpacity
                style={styles.sideButton}
                onPress={() => router.replace('/')}
            >
                {/* Fallback to pathname check if isPanel hook is unreliable, but hook seemed fine for panel */}
                <PanelIcon active={isPanel} color={theme.accent} />
            </TouchableOpacity>

            {/* INSTRUTOR (CENTRAL) */}
            <InstructorButton />

            {/* CONTINUAR (DIREITA) - Replaces Profile */}
            <TouchableOpacity
                style={styles.sideButton}
                onPress={() => router.replace('/continuar')}
            >
                <ContinuarIcon active={isContinuar} color={theme.accent} />
            </TouchableOpacity>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flexDirection: 'row',
        height: Platform.OS === 'ios' ? 80 : 70,
        alignItems: 'center',
        justifyContent: 'space-around',
        borderTopWidth: 1,
        paddingBottom: Platform.OS === 'ios' ? 20 : 0,
    },
    sideButton: {
        flex: 1,
        alignItems: 'center',
        justifyContent: 'center',
        height: '100%',
    },
});
