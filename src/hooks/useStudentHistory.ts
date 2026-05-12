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

        try {
            // v_historico_atividade_recruta_v3 é a view READ-ONLY canônica para histórico.
            // v_audit_eventos é writeable view com trigger — não consumir para leitura.
            const { data, error } = await supabase
                .from('v_historico_atividade_recruta_v3')
                .select('*')
                .order('created_at', { ascending: false });

            if (error) throw error;

            // Campos da view correspondem diretamente ao tipo StudentHistoryItem
            const mapped = (data ?? []).map((item: any) => ({
                history_id: item.id || Math.random().toString(),
                event_type: item.event_type || 'system',
                title: item.title || 'Evento',
                description: item.description || '',
                created_at: item.created_at
            }));
            setHistory(mapped);
        } catch (err) {
            console.error('[HISTORICO] Erro ao carregar histórico (Silencioso):', err);
            setHistory([]);
        } finally {
            setLoading(false);
        }
    }

    useEffect(() => {
        loadHistory();
    }, []);

    return {
        history,
        loading,
    };
}
