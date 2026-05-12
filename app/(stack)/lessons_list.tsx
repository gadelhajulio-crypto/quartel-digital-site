import React, { useEffect, useState } from 'react';
import { View, Text, SectionList, Pressable, StyleSheet, ActivityIndicator, Alert, ToastAndroid, Platform } from "react-native";
import { useForceTheme } from "../../src/context/ForceThemeContext";
import { useRouter } from "expo-router";
import { Header } from "../../src/components/Header";
import { fetchLessons } from "../../src/services/lessons";
import { isLessonBlocked } from "../../src/utils/accessControl";
import { Ionicons } from '@expo/vector-icons';

export default function Aulas() {
    const router = useRouter();
    const { theme } = useForceTheme(); // Dynamic theme
    const [sections, setSections] = useState<any[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        loadLessons();
    }, []);

    const loadLessons = async () => {
        try {
            const { data, error } = await fetchLessons();
            if (error) {
                console.error("Error fetching lessons:", error);
                return;
            }

            if (data) {
                // Group by module
                const grouped = data.reduce((acc: any, lesson: any) => {
                    const mod = lesson.module || 'Sem Módulo';
                    if (!acc[mod]) {
                        acc[mod] = [];
                    }
                    acc[mod].push(lesson);
                    return acc;
                }, {});

                const sectionsArray = Object.keys(grouped).map(key => ({
                    title: formatModuleName(key),
                    data: grouped[key]
                }));

                setSections(sectionsArray);
            }
        } catch (err) {
            console.error(err);
        } finally {
            setLoading(false);
        }
    };

    const formatModuleName = (name: string) => {
        return name.split('-').map(word => word.charAt(0).toUpperCase() + word.slice(1)).join(' ');
    };

    const handlePress = (lesson: any, blocked: boolean) => {
        if (blocked) {
            if (Platform.OS === 'android') {
                ToastAndroid.show("Conteúdo exclusivo", ToastAndroid.SHORT);
            } else {
                Alert.alert("Bloqueado", "Conteúdo exclusivo para assinantes.");
            }
            return;
        }
        router.push({
            pathname: "/aula/[id]",
            params: { id: lesson.id }
        });
    };

    // Dynamic Styles Definition
    const styles = getStyles(theme);

    if (loading) {
        return (
            <View style={{ flex: 1, backgroundColor: theme.background, justifyContent: 'center', alignItems: 'center' }}>
                <ActivityIndicator size="large" color={theme.textPrimary} />
            </View>
        );
    }

    return (
        <View style={{ flex: 1, backgroundColor: theme.background, padding: 16 }}>
            <Header title="LISTA DE AULAS" />
            <SectionList
                sections={sections}
                keyExtractor={(item) => item.id}
                renderSectionHeader={({ section: { title } }) => (
                    <Text style={styles.sectionHeader}>{title}</Text>
                )}
                renderItem={({ item }) => {
                    const blocked = isLessonBlocked(item);
                    return (
                        <Pressable
                            style={[styles.card, blocked && { opacity: 0.5 }]}
                            onPress={() => handlePress(item, blocked)}
                        >
                            <View style={{ flex: 1 }}>
                                <Text style={styles.title}>{item.title}</Text>
                                <Text style={styles.desc}>{item.description}</Text>
                            </View>
                            {blocked && (
                                <Ionicons name="lock-closed" size={20} color={theme.textSecondary} style={{ marginLeft: 8 }} />
                            )}
                        </Pressable>
                    );
                }}
            />
        </View>
    );
}

const getStyles = (theme: any) => StyleSheet.create({
    sectionHeader: {
        fontSize: 18,
        fontWeight: 'bold',
        color: theme.textPrimary, // Updated property name
        marginTop: 16,
        marginBottom: 8,
        paddingHorizontal: 4,
    },
    card: {
        backgroundColor: theme.card, // Updated property name
        padding: 16,
        borderRadius: 12,
        marginBottom: 12,
        flexDirection: 'row',
        alignItems: 'center',
        justifyContent: 'space-between',
    },
    title: {
        color: theme.textPrimary, // Updated property name
        fontSize: 16,
        fontWeight: "700",
    },
    desc: {
        color: theme.textSecondary, // Updated property name
        fontSize: 12,
        marginTop: 4
    }
});
