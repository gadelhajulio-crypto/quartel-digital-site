import React from 'react';
import { View, StyleSheet, TouchableOpacity, Text, ImageBackground } from 'react-native';
import { theme } from '../theme';

type VideoPlaceholderProps = {
    onPlay?: () => void;
    color?: string; // Theme primary color
    title?: string;
};

export function VideoPlaceholder({ onPlay, color = theme.colors.oliveGreen, title }: VideoPlaceholderProps) {
    return (
        <View style={[styles.container, { borderColor: color }]}>
            <View style={[styles.overlay, { backgroundColor: color }]}>
                {/* Simulating a thumbnail overlay with force color tint */}
            </View>

            <TouchableOpacity onPress={onPlay} style={styles.playButtonContainer}>
                <View style={[styles.playButtonCircle, { borderColor: theme.colors.gold }]}>
                    <View style={[styles.playTriangle, { borderLeftColor: theme.colors.gold }]} />
                </View>
            </TouchableOpacity>

            {title && (
                <Text style={styles.videoTitle}>{title}</Text>
            )}
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        width: '100%',
        aspectRatio: 16 / 9,
        backgroundColor: '#000',
        borderRadius: 8,
        borderWidth: 1,
        overflow: 'hidden',
        justifyContent: 'center',
        alignItems: 'center',
        marginBottom: theme.spacing.m,
    },
    overlay: {
        ...StyleSheet.absoluteFillObject,
        opacity: 0.2,
    },
    playButtonContainer: {
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 10,
    },
    playButtonCircle: {
        width: 60,
        height: 60,
        borderRadius: 30,
        borderWidth: 3,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: 'rgba(0,0,0,0.6)',
    },
    playTriangle: {
        width: 0,
        height: 0,
        backgroundColor: 'transparent',
        borderStyle: 'solid',
        borderTopWidth: 10,
        borderBottomWidth: 10,
        borderLeftWidth: 20,
        borderTopColor: 'transparent',
        borderBottomColor: 'transparent',
        marginLeft: 4, // Visual centering
    },
    videoTitle: {
        position: 'absolute',
        bottom: 10,
        left: 10,
        color: '#FFF',
        fontWeight: 'bold',
        textShadowColor: 'rgba(0,0,0,0.8)',
        textShadowOffset: { width: 1, height: 1 },
        textShadowRadius: 2,
    }
});
