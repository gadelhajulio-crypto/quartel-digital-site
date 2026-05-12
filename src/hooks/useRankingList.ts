import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { startOfMonth, format } from 'date-fns';

// Assuming view returns flat structure: user_id, rank_position, xp_mensal, full_name (or similar)
export interface RankingItem {
    user_id: string;
    xp_mensal: number;
    full_name?: string;
    war_name?: string;
    avatar_url?: string;
}

export function useRankingList(userForce: string) {
    const [rankingList, setRankingList] = useState<RankingItem[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        // Disable Ranking Query for Test Build
        // To prevent invalid column errors and visual noise
        setRankingList([]);
        setLoading(false);
    }, [userForce]);

    return { rankingList, loading };
}
