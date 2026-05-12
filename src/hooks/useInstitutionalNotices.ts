import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

export interface InstitutionalNotice {
    notice_id: string;
    title: string;
    body: string;
    created_at: string;
    priority: number;
    deep_link?: string | null;
    is_read: boolean;
}

export function useInstitutionalNotices() {
    const [notices, setNotices] = useState<InstitutionalNotice[]>([]);
    const [loading, setLoading] = useState(true);

    async function loadNotices() {
        setLoading(true);

        const { data, error } = await supabase
            .from('v_institutional_notices')
            .select('*')
            .order('priority', { ascending: false })
            .order('created_at', { ascending: false });

        if (error) {
            console.error('[AVISOS] Erro ao carregar avisos:', error);
            setNotices([]);
        } else {
            setNotices(data ?? []);
        }

        setLoading(false);
    }

    async function markAsRead(noticeId: string) {
        // rpc_mark_notice_read: idempotente via ON CONFLICT DO NOTHING no banco
        await supabase.rpc('rpc_mark_notice_read', { p_notice_id: noticeId });

        // Atualização local apenas para refletir UI imediatamente
        setNotices((prev) =>
            prev.map((n) =>
                n.notice_id === noticeId ? { ...n, is_read: true } : n
            )
        );
    }

    useEffect(() => {
        loadNotices();
    }, []);

    return {
        notices,
        loading,
        markAsRead,
    };
}
