import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

export interface HistoryEvent {
    id: string; // Assuming view has some ID or we rely on index
    created_at: string;
    description: string;
    impacto: string | number | null; // XP or other
    referencia: string | null; // 'aula', 'medalha', etc.
    source_id?: string | null; // For navigation
}

export function useHistory(userId: string) {
    const [history, setHistory] = useState<HistoryEvent[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        if (!userId) {
            setLoading(false);
            return;
        }

        async function fetchHistory() {
            try {
                // Querying the view exactly as requested
                const { data, error } = await supabase
                    .from('v_historico_atividade_recruta_v3')
                    .select('*');
                // Assuming the view is already ordered by date desc as per prompt requirement ("Ordenação já vem do banco")
                // If not, prompt says "Ordenação já vem do banco (não ordenar no app)"

                if (error) {
                    console.error('Error fetching history:', error);
                } else {
                    setHistory(data || []);
                }
            } catch (err) {
                console.error('Unexpected error fetching history:', err);
            } finally {
                setLoading(false);
            }
        }

        fetchHistory();
    }, [userId]);

    return { history, loading };
}
