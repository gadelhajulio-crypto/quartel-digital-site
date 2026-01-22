import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

export interface AvailableReview {
    review_id: string;
    lesson_title: string;
    type: 'audio' | 'video';
    status: 'available' | 'blocked';
}

export function useAvailableReviews() {
    const [reviews, setReviews] = useState<AvailableReview[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        let active = true;

        async function loadReviews() {
            setLoading(true);

            const { data, error } = await supabase
                .from('v_available_reviews') // view pronta no backend
                .select('*')
                .order('lesson_order');

            if (!active) return;

            if (error) {
                console.error('[REVIEWS] Erro ao carregar revisões:', error);
                setReviews([]);
            } else {
                setReviews(data ?? []);
            }

            setLoading(false);
        }

        loadReviews();

        return () => {
            active = false;
        };
    }, []);

    return {
        reviews,
        loading,
    };
}
