import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

export interface MedalStatus {
    medal_id: string;
    name: string;
    description: string;
    level: 'none' | 'bronze' | 'silver' | 'gold';
    achieved: boolean;
}

export function useMedals() {
    const [medals, setMedals] = useState<MedalStatus[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        let active = true;

        async function loadMedals() {
            setLoading(true);

            const { data, error } = await supabase
                .from('v_medals_status_v3')
                .select('*')
                .order('name');

            if (!active) return;

            if (error) {
                console.error('[MEDALS] Erro ao carregar medalhas:', error);
                setMedals([]);
            } else {
                setMedals(data ?? []);
            }

            setLoading(false);
        }

        loadMedals();

        return () => {
            active = false;
        };
    }, []);

    return {
        medals,
        loading,
    };
}
