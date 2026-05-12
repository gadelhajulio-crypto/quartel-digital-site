import React, { useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useForceTheme } from '@/context/ForceThemeContext';

interface Lesson {
    title: string;
    locked: boolean;
}

interface ModuleAccordionProps {
    title: string;
    lessons: Lesson[];
    moduleIndex: number;
}

export function ModuleAccordion({ title, lessons, moduleIndex }: ModuleAccordionProps) {
    const { theme } = useForceTheme();
    const [expanded, setExpanded] = useState(moduleIndex === 0);

    return (
        <View style={[styles.container, { backgroundColor: theme.card, borderColor: theme.border }]}>
            <TouchableOpacity
                style={styles.header}
                onPress={() => setExpanded(!expanded)}
                activeOpacity={0.8}
            >
                <Text style={[styles.title, { color: theme.textPrimary }]}>{title}</Text>
                <Ionicons
                    name={expanded ? "chevron-up" : "chevron-down"}
                    size={20}
                    color={theme.textSecondary}
                />
            </TouchableOpacity>

            {expanded && (
                <View style={[styles.content, { borderTopColor: theme.border }]}>
                    {lessons.map((lesson, index) => (
                        <View key={index} style={styles.lessonRow}>
                            <View style={[styles.statusIcon, {
                                borderColor: lesson.locked ? theme.textSecondary : '#2D6A4F',
                                backgroundColor: lesson.locked ? 'transparent' : '#2D6A4F'
                            }]}>
                                {lesson.locked ? (
                                    <Ionicons name="lock-closed" size={10} color={theme.textSecondary} />
                                ) : (
                                    <Ionicons name="play" size={10} color={theme.background} />
                                )}
                            </View>
                            <Text style={[styles.lessonTitle, {
                                color: lesson.locked ? theme.textSecondary : theme.textPrimary
                            }]}>
                                {index + 1}. {lesson.title}
                            </Text>
                        </View>
                    ))}
                </View>
            )}
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        borderRadius: 12,
        marginBottom: 12,
        borderWidth: 1,
        overflow: 'hidden',
    },
    header: {
        padding: 16,
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
    },
    title: {
        fontSize: 16,
        fontWeight: 'bold',
        flex: 1,
        marginRight: 8,
    },
    content: {
        borderTopWidth: 1,
        padding: 16,
    },
    lessonRow: {
        flexDirection: 'row',
        alignItems: 'center',
        marginBottom: 16,
    },
    statusIcon: {
        width: 24,
        height: 24,
        borderRadius: 12,
        borderWidth: 1.5,
        justifyContent: 'center',
        alignItems: 'center',
        marginRight: 12,
    },
    lessonTitle: {
        fontSize: 14,
        flex: 1,
        lineHeight: 20,
    }
});
