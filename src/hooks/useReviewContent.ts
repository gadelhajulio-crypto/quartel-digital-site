import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

interface ReviewContent {
    review_id: string;
    lesson_title: string;
    type: 'audio' | 'video';
    media_url: string;
}

export function useReviewContent(reviewId: string) {
    const [content, setContent] = useState<ReviewContent | null>(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        let active = true;

        async function load() {
            setLoading(true);

            const { data, error } = await supabase
                .from('v_review_content') // view pronta no backend
                .select('*')
                .eq('review_id', reviewId)
                .single();

            if (!active) return;

            if (error) {
                console.error('[REVIEW CONTENT] Erro ao carregar revisão:', error);
                setContent(null);
            } else {
                setContent(data);
            }

            setLoading(false);
        }

        if (reviewId) load();

        return () => {
            active = false;
        };
    }, [reviewId]);

    return { content, loading };
}
