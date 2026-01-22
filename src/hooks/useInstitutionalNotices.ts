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
        // Registro simples de leitura (sem lógica de decisão)
        await supabase
            .from('institutional_notice_reads')
            .insert({ notice_id: noticeId });

        // Atualização local apenas para refletir UI
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
