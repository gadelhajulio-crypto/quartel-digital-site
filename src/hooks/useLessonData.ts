import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { Lesson } from '../types/lesson';

export function useLessonData(lessonId: string, userId?: string) {
    const [data, setData] = useState<Lesson | null>(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        async function load() {
            if (!userId || !lessonId) {
                setLoading(false);
                return;
            }

            // Updated to use strict schema: lesson_progress
            const { data, error } = await supabase
                .from('lessons')
                .select(`
          id,
          title,
          module,
          lesson_order,
          lesson_media (
            id,
            type,
            url
          ),
          lesson_progress (
            completed_at,
            user_id
          )
        `)
                .eq('id', lessonId)
                .eq('lesson_progress.user_id', userId)
                .maybeSingle();

            if (error) {
                console.error('Error fetching lesson data:', error);
            }

            const adaptedData: any = data;

            // Adapt array response from 1:N relation to single object for UI consumption
            if (adaptedData && Array.isArray(adaptedData.lesson_progress)) {
                adaptedData.lesson_progress = adaptedData.lesson_progress.find((p: any) => p.user_id === userId) || null;
            }

            setData(adaptedData as Lesson);
            setLoading(false);
        }

        load();
    }, [lessonId, userId]);

    return { data, loading };
}
