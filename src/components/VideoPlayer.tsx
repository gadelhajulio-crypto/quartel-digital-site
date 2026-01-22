import React from 'react';
import { View, StyleSheet } from "react-native";
import { Video, ResizeMode } from "expo-av";

export function VideoPlayer({ uri }: { uri: string }) {
    return (
        <View style={styles.container}>
            <Video
                source={{ uri }}
                useNativeControls
                resizeMode={ResizeMode.CONTAIN}
                style={styles.video}
            />
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        height: 220,
        backgroundColor: "#000",
    },
    video: {
        width: "100%",
        height: "100%",
    },
});
