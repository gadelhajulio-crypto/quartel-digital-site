import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

export interface InstructorMessage {
    message_id: string;
    title: string;
    body: string;
    created_at: string;
    deep_link?: string | null;
    is_read: boolean;
}

export function useInstructorMessages() {
    const [messages, setMessages] = useState<InstructorMessage[]>([]);
    const [loading, setLoading] = useState(true);

    async function loadMessages() {
        setLoading(true);

        const { data, error } = await supabase
            .from('v_instructor_messages')
            .select('*')
            .order('created_at', { ascending: false });

        if (error) {
            console.error('[INSTRUTOR] Erro ao carregar mensagens:', error);
            setMessages([]);
        } else {
            setMessages(data ?? []);
        }

        setLoading(false);
    }

    async function markAsRead(messageId: string) {
        // rpc_mark_instructor_message_read: idempotente via ON CONFLICT DO NOTHING no banco
        await supabase.rpc('rpc_mark_instructor_message_read', { p_message_id: messageId });

        setMessages((prev) =>
            prev.map((m) =>
                m.message_id === messageId ? { ...m, is_read: true } : m
            )
        );
    }

    useEffect(() => {
        loadMessages();
    }, []);

    return {
        messages,
        loading,
        markAsRead,
    };
}
