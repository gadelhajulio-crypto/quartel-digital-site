import React, { useState, useRef, useEffect } from 'react';
import { View, Text, TextInput, FlatList, KeyboardAvoidingView, Platform, StyleSheet, TouchableOpacity, ActivityIndicator, Image } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useForceTheme } from '../../src/context/ForceThemeContext';
import { Ionicons } from '@expo/vector-icons';
import { supabase } from '../../src/lib/supabase';
import { useAuth } from '../../src/context/AuthContext';


type Message = {
    id: string;
    text: string;
    sender: 'user' | 'instructor';
    timestamp: Date;
};

// Assuming instructors avatars are globally accessible or we reuse the logic
// Since we don't want to over-engineer the import, we'll map simple IDs to same assets or avatars
// For chat, usually a small avatar is enough.
const AVATARS: Record<string, any> = {
    'objetivo': require('../../assets/instructors/marinha/objetivo/instrutor-objetivo-marinha-selecao.png'), // Reusing valid asset
    'estrategico': require('../../assets/instructors/marinha/estrategico/instrutor-estrategico-marinha-selecao.png'),
    'didatico': require('../../assets/instructors/marinha/didatica/instrutor-didatica-marinha-selecao.png'),
};

import { sendChatMessage } from '../../src/services/chatService';

export default function ChatScreen() {
    const { theme } = useForceTheme();
    const { session, user, profile } = useAuth(); // Use explicit context
    const [messages, setMessages] = useState<Message[]>([]);
    const [inputText, setInputText] = useState('');
    const [loading, setLoading] = useState(false);
    const [isTyping, setIsTyping] = useState(false);
    const flatListRef = useRef<FlatList>(null);

    const instructorId = profile?.instructor_profile_id || 'objetivo'; // Use profile directly

    // Removed manual profile fetch useEffect since useAuth handles it.

    const sendMessage = async () => {
        if (!inputText.trim()) return;

        const userMsg: Message = {
            id: Date.now().toString(),
            text: inputText,
            sender: 'user',
            timestamp: new Date(),
        };

        setMessages((prev) => [...prev, userMsg]);
        setInputText('');
        setLoading(true);
        setIsTyping(true);

        setTimeout(() => flatListRef.current?.scrollToEnd(), 100);

        try {
            // CENTRALIZED PAYLOAD call
            const data = await sendChatMessage(userMsg.text, user, profile);

            const humanDelay = Math.floor(Math.random() * 600) + 600;

            setTimeout(() => {
                const replyMsg: Message = {
                    id: (Date.now() + 1).toString(),
                    text: data.reply,
                    sender: 'instructor',
                    timestamp: new Date(),
                };

                setIsTyping(false);
                setMessages((prev) => [...prev, replyMsg]);
                setTimeout(() => flatListRef.current?.scrollToEnd(), 100);
            }, humanDelay);

        } catch (err: any) {
            console.error(err);
            setIsTyping(false);
            const errorMsg: Message = {
                id: Date.now().toString(),
                text: err.message || "Falha na conexão com o QG. Tente novamente.",
                sender: 'instructor',
                timestamp: new Date(),
            };
            setMessages((prev) => [...prev, errorMsg]);
        } finally {
            setLoading(false);
        }
    };

    const renderMessage = ({ item }: { item: Message }) => {
        const isUser = item.sender === 'user';

        return (
            <View
                style={[
                    styles.messageBubble,
                    isUser
                        ? { backgroundColor: theme.primary, alignSelf: 'flex-end', borderBottomRightRadius: 2 }
                        : { backgroundColor: theme.card, alignSelf: 'flex-start', borderBottomLeftRadius: 2 }
                ]}
            >
                <Text style={[
                    styles.messageText,
                    { color: isUser ? '#000' : theme.textPrimary }
                ]}>
                    {item.text}
                </Text>
                <Text style={[styles.timeText, { color: isUser ? 'rgba(0,0,0,0.5)' : theme.textSecondary }]}>
                    {item.timestamp.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                </Text>
            </View>
        );
    };

    return (
        <SafeAreaView style={[styles.container, { backgroundColor: theme.background }]} edges={['top']}>
            <View style={[styles.header, { borderBottomColor: 'rgba(255,255,255,0.05)' }]}>
                <View style={{ flexDirection: 'row', alignItems: 'center' }}>
                    <View style={styles.avatarContainer}>
                        <Image source={AVATARS[instructorId]} style={styles.avatar} resizeMode="cover" />
                        <View style={styles.onlineBadge} />
                    </View>
                    <View>
                        <Text style={[styles.headerTitle, { color: theme.textPrimary }]}>INSTRUTOR</Text>
                        <Text style={[styles.headerSubtitle, { color: theme.textSecondary }]}>Link Seguro • QG</Text>
                    </View>
                </View>
            </View>

            <FlatList
                ref={flatListRef}
                data={messages}
                keyExtractor={(item) => item.id}
                renderItem={renderMessage}
                contentContainerStyle={styles.listContent}
                onContentSizeChange={() => flatListRef.current?.scrollToEnd()}
            />

            {/* Typing Indicator Area */}
            {isTyping && (
                <View style={{ paddingHorizontal: 20, paddingBottom: 10 }}>
                    <Text style={{ color: theme.textSecondary, fontSize: 12, fontStyle: 'italic' }}>
                        Instrutor está digitando...
                    </Text>
                </View>
            )}

            <KeyboardAvoidingView
                behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
                keyboardVerticalOffset={Platform.OS === 'ios' ? 90 : 0}
            >
                <View style={[styles.inputContainer, { backgroundColor: theme.card }]}>
                    <TextInput
                        style={[styles.input, { color: theme.textPrimary, backgroundColor: theme.background }]}
                        value={inputText}
                        onChangeText={setInputText}
                        placeholder="Digite sua dúvida..."
                        placeholderTextColor={theme.textSecondary}
                        multiline
                    />
                    <TouchableOpacity
                        onPress={sendMessage}
                        disabled={!inputText.trim()}
                        style={[styles.sendButton, { backgroundColor: inputText.trim() ? theme.primary : '#333' }]}
                    >
                        {loading ? <ActivityIndicator color="#000" size="small" /> : <Ionicons name="send" size={20} color={inputText.trim() ? "#000" : "#666"} />}
                    </TouchableOpacity>
                </View>
            </KeyboardAvoidingView>
        </SafeAreaView>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
    },
    header: {
        padding: 16,
        borderBottomWidth: 1,
        flexDirection: 'row',
        alignItems: 'center',
    },
    avatarContainer: {
        width: 40,
        height: 40,
        borderRadius: 20,
        marginRight: 12,
        overflow: 'visible',
        backgroundColor: '#333'
    },
    avatar: {
        width: '100%',
        height: '100%',
        borderRadius: 20
    },
    onlineBadge: {
        position: 'absolute',
        bottom: 0,
        right: 0,
        width: 12,
        height: 12,
        borderRadius: 6,
        backgroundColor: '#4CAF50',
        borderWidth: 2,
        borderColor: '#000'
    },
    headerTitle: {
        fontSize: 16,
        fontWeight: 'bold',
        letterSpacing: 1,
    },
    headerSubtitle: {
        fontSize: 12,
    },
    listContent: {
        padding: 16,
        paddingBottom: 32,
    },
    messageBubble: {
        maxWidth: '80%',
        padding: 12,
        borderRadius: 16,
        marginBottom: 12,
    },
    messageText: {
        fontSize: 16,
        lineHeight: 22,
    },
    timeText: {
        fontSize: 10,
        marginTop: 4,
        alignSelf: 'flex-end',
    },
    inputContainer: {
        padding: 16,
        paddingBottom: Platform.OS === 'ios' ? 34 : 16, // Extra padding for home bar
        flexDirection: 'row',
        alignItems: 'center',
        borderTopWidth: 1,
        borderTopColor: 'rgba(255,255,255,0.05)',
    },
    input: {
        flex: 1,
        borderRadius: 20,
        paddingHorizontal: 16,
        paddingVertical: 10,
        maxHeight: 100,
        marginRight: 12,
    },
    sendButton: {
        width: 44,
        height: 44,
        borderRadius: 22,
        justifyContent: 'center',
        alignItems: 'center',
    },
});
