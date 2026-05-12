import React from 'react';
import { View, Text, StyleSheet, ImageBackground } from 'react-native';
import { useForceTheme } from '../../context/ForceThemeContext';
import { useAuth } from '../../context/AuthContext';

export function DashboardHeader() {
    const { theme, force } = useForceTheme();
    const { profile } = useAuth();

    // Fallback images based on force (using placeholders or assets referenced in conversation logs if any, otherwise generic)
    // Using generic placeholders for now, assuming assets folder structure
    const getBackgroundImage = () => {
        // In a real scenario, these would be require('../../assets/navy_ship.png') etc.
        // Since I don't have the file list of assets, I'll use a color gradient for now 
        // OR simpler: render nothing and let the background/overlay do the work if no asset.
        // However, requirements asked for "Inagem discreta contextual".
        return null;
    };

    const period = new Date().getHours() < 12 ? 'Bom dia' : new Date().getHours() < 18 ? 'Boa tarde' : 'Boa noite';
    const userName = profile?.nome_guerra || profile?.nome?.split(' ')[0] || 'Recruta';

    return (
        <View style={styles.container}>
            {/* Header Background - Placeholder for Image */}
            <View style={[styles.imageContainer, { backgroundColor: theme.dashboard.accent }]}>
                <View style={[styles.overlay, { backgroundColor: theme.dashboard.headerOverlay }]} />
            </View>

            <View style={styles.content}>
                <Text style={[styles.greeting, { color: theme.dashboard.textSecondary }]}>
                    {period},
                </Text>
                <Text style={[styles.name, { color: theme.dashboard.textPrimary }]}>
                    {userName}
                </Text>
            </View>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        paddingTop: 60, // Safe Area top
        paddingHorizontal: 20,
        paddingBottom: 20,
        marginBottom: 10,
    },
    imageContainer: {
        ...StyleSheet.absoluteFillObject,
        height: 200,
        opacity: 0.1, // Discreta
    },
    overlay: {
        ...StyleSheet.absoluteFillObject,
    },
    content: {
        zIndex: 1,
    },
    greeting: {
        fontSize: 16,
        fontWeight: '400',
    },
    name: {
        fontSize: 28,
        fontWeight: '700',
        letterSpacing: -0.5,
    }
});
