import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

export interface StudentHistoryItem {
    history_id: string;
    event_type: 'lesson' | 'review' | 'xp' | 'medal' | 'system';
    title: string;
    description: string;
    created_at: string;
}

export function useStudentHistory() {
    const [history, setHistory] = useState<StudentHistoryItem[]>([]);
    const [loading, setLoading] = useState(true);

    async function loadHistory() {
        setLoading(true);

        const { data, error } = await supabase
            .from('v_student_history')
            .select('*')
            .order('created_at', { ascending: false });

        if (error) {
            console.error('[HISTORICO] Erro ao carregar histórico:', error);
            setHistory([]);
        } else {
            setHistory(data ?? []);
        }

        setLoading(false);
    }

    useEffect(() => {
        loadHistory();
    }, []);

    return {
        history,
        loading,
    };
}
