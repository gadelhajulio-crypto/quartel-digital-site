import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { startOfMonth, format } from 'date-fns';

export interface RankingItem {
    user_id: string;
    rank_position: number;
    xp_mensal: number;
    profiles: {
        full_name?: string;
        name?: string;
        war_name?: string;
        // Add other potential name fields
    } | null;
}

export function useRankingList(userForce: string) {
    const [rankingList, setRankingList] = useState<RankingItem[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        async function load() {
            if (!userForce) {
                setLoading(false);
                return;
            }

            const currentMonth = format(startOfMonth(new Date()), 'yyyy-MM-dd');

            const { data, error } = await supabase
                .from('mv_ranking_mensal')
                .select(`
            user_id,
            rank_position,
            xp_mensal,
            profiles:user_id (
                full_name
            )
        `)
                .eq('force', userForce)
                .eq('month_ref', currentMonth)
                .order('rank_position', { ascending: true })
                .limit(50); // Limit to top 50 for performance and relevance

            if (error) {
                console.error('Error fetching ranking:', error);
            } else {
                setRankingList(data as unknown as RankingItem[]);
            }
            setLoading(false);
        }

        load();
    }, [userForce]);

    return { rankingList, loading };
}
