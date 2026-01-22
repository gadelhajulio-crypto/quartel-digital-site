import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';

export type NextLesson = {
    lesson_id: string;
    title: string;
    module: string;
    lesson_order: number;
    status: 'available' | 'completed' | 'blocked';
};

export function useNextLesson(userId?: string) {
    const [nextLesson, setNextLesson] = useState<NextLesson | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<any>(null);

    useEffect(() => {
        if (!userId) {
            setLoading(false);
            return;
        }

        async function fetchNext() {
            try {
                setLoading(true);
                const { data, error } = await supabase
                    .rpc('get_student_next_lesson', { p_user_id: userId })
                    .maybeSingle();

                if (error) throw error;
                setNextLesson(data);
            } catch (err) {
                console.error('Error fetching next lesson:', err);
                setError(err);
            } finally {
                setLoading(false);
            }
        }

        fetchNext();
    }, [userId]);

    return { nextLesson, loading, error };
}
