import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

export interface MedalStatus {
    id: string; // or name as key
    nome: string;
    status: 'concedida' | 'elegível' | 'não elegível' | 'bloqueada'; // mapped to 'não elegível' from view
    criterio_faltante: string | null;
    descricao?: string; // Optional if view has it
    image_url?: string; // Optional
}

export function useMedals(userId: string) {
    const [medals, setMedals] = useState<MedalStatus[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        if (!userId) {
            setLoading(false);
            return;
        }

        async function fetchMedals() {
            try {
                const { data, error } = await supabase
                    .from('v_medalha_elegibilidade_status')
                    .select('*');

                if (error) {
                    console.error('Error fetching medals:', error);
                } else {
                    setMedals(data || []);
                }
            } catch (err) {
                console.error('Unexpected error fetching medals:', err);
            } finally {
                setLoading(false);
            }
        }

        fetchMedals();
    }, [userId]);

    return { medals, loading };
}
