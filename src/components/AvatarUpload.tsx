import React, { useState, useEffect } from 'react';
import { View, Image, StyleSheet, TouchableOpacity, Alert, ActivityIndicator, Text } from 'react-native';
import * as ImagePicker from 'expo-image-picker';
import { supabase } from '../../_lib/supabase';
import { theme } from '../theme';

type AvatarUploadProps = {
    size?: number;
    url?: string | null;
    onUpload: (url: string) => void;
    editable?: boolean;
    color?: string; // Force theme color
};

export function AvatarUpload({ size = 150, url, onUpload, editable = false, color = theme.colors.gold }: AvatarUploadProps) {
    const [uploading, setUploading] = useState(false);
    const [avatarUrl, setAvatarUrl] = useState<string | null>(null);

    useEffect(() => {
        if (url) downloadImage(url);
    }, [url]);

    async function downloadImage(path: string) {
        try {
            const { data, error } = await supabase.storage.from('avatars').download(path);
            if (error) {
                throw error;
            }
            const fr = new FileReader();
            fr.readAsDataURL(data);
            fr.onload = () => {
                setAvatarUrl(fr.result as string);
            };
        } catch (error) {
            console.log('Error downloading image: ', error);
        }
    }

    async function uploadAvatar() {
        try {
            setUploading(true);

            const result = await ImagePicker.launchImageLibraryAsync({
                mediaTypes: ImagePicker.MediaTypeOptions.Images,
                allowsEditing: true,
                aspect: [1, 1],
                quality: 1,
                base64: true,
            });

            if (result.canceled || !result.assets || result.assets.length === 0) {
                return;
            }

            const image = result.assets[0];
            const fileExt = image.uri.split('.').pop();
            const fileName = `${Date.now()}.${fileExt}`;
            const filePath = `${fileName}`;

            // Upload logic for Supabase (using base64 mainly for Expo go compat simplified)
            const { error: uploadError } = await supabase.storage
                .from('avatars')
                .upload(filePath, decode(image.base64!), {
                    contentType: 'image/png',
                });

            if (uploadError) {
                throw uploadError;
            }

            onUpload(filePath);
        } catch (error) {
            if (error instanceof Error) {
                Alert.alert('Erro no upload', error.message);
            } else {
                throw error;
            }
        } finally {
            setUploading(false);
        }
    }

    // Helper to decode base64 string to array buffer
    function decode(base64: string) {
        const binaryString = atob(base64);
        const len = binaryString.length;
        const bytes = new Uint8Array(len);
        for (let i = 0; i < len; i++) {
            bytes[i] = binaryString.charCodeAt(i);
        }
        return bytes.buffer;
    }


    return (
        <View>
            {avatarUrl ? (
                <Image
                    source={{ uri: avatarUrl }}
                    style={[styles.avatar, { width: size, height: size, borderColor: color }]}
                />
            ) : (
                <View style={[styles.avatar, { width: size, height: size, borderColor: color, backgroundColor: 'rgba(255,255,255,0.1)', justifyContent: 'center', alignItems: 'center' }]}>
                    <Text style={{ fontSize: size * 0.4 }}>👤</Text>
                </View>
            )}

            {editable && (
                <TouchableOpacity
                    style={[styles.editButton, { backgroundColor: color }]}
                    onPress={uploadAvatar}
                    disabled={uploading}
                >
                    {uploading ? (
                        <ActivityIndicator size="small" color="#000" />
                    ) : (
                        <Text style={{ fontSize: 16 }}>📷</Text>
                    )}
                </TouchableOpacity>
            )}
        </View>
    );
}

const styles = StyleSheet.create({
    avatar: {
        borderRadius: 1000, // Circle
        borderWidth: 2,
    },
    editButton: {
        position: 'absolute',
        bottom: 0,
        right: 0,
        padding: 8,
        borderRadius: 20,
        elevation: 5,
    }
});
