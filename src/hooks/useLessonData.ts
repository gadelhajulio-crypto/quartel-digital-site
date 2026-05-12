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

            // 1. Fetch Lesson Data from VIEW
            const { data: lessonData, error: lessonError } = await supabase
                .from('v_lessons_panel')
                .select('*')
                .eq('lesson_id', lessonId)
                .maybeSingle();

            if (lessonError) {
                console.error('Error fetching lesson data:', lessonError);
                setLoading(false);
                return;
            }

            if (!lessonData) {
                setLoading(false);
                return;
            }

            // 2. Fetch Progress from VIEW
            const { data: progressData } = await supabase
                .from('v_lesson_progress_panel')
                .select('completed_at')
                .eq('lesson_id', lessonId)
                .eq('recruta_id', userId)
                .maybeSingle();

            // 3. Adapt to Lesson interface (contrato C6 — v_lessons_panel)
            const adaptedLesson: Lesson = {
                lesson_id: lessonData.lesson_id,
                title: lessonData.title,
                module: lessonData.module,
                lesson_order: lessonData.lesson_order,
                force: lessonData.force,
                video_url: lessonData.video_url ?? null,
                pdf_url: lessonData.pdf_url ?? null,
                completed_at: progressData?.completed_at ?? null,
            };

            setData(adaptedLesson);
            setLoading(false);
        }

        load();
    }, [lessonId, userId]);

    return { data, loading };
}
