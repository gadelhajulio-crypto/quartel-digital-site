import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { startOfMonth, format } from 'date-fns';

export interface ChampionData {
    user_id: string;
    force: string;
    month_ref: string;
    profiles: {
        full_name?: string;
        name?: string;
        war_name?: string;
    } | null;
}

export function useMonthlyChampion(userForce: string) {
    const [champion, setChampion] = useState<ChampionData | null>(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        async function load() {
            if (!userForce) {
                setLoading(false);
                return;
            }

            const currentMonth = format(startOfMonth(new Date()), 'yyyy-MM-dd');

            const { data, error } = await supabase
                .from('mv_campeao_mensal')
                .select(`
            user_id,
            force,
            month_ref,
            profiles:user_id (
                full_name,
                name,
                war_name
            )
        `)
                .eq('force', userForce)
                .eq('month_ref', currentMonth)
                .maybeSingle();

            if (error) {
                console.error('Error fetching champion:', error);
            } else {
                setChampion(data as unknown as ChampionData);
            }
            setLoading(false);
        }

        load();
    }, [userForce]);

    return { champion, loading };
}
