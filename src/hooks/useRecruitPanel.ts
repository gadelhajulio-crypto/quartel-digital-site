import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { startOfMonth, format } from 'date-fns';

export function useRecruitPanel(userId: string, userForce: string) {
    const [xp, setXp] = useState(0);
    const [ranking, setRanking] = useState(0);
    const [completed, setCompleted] = useState(0);
    const [isChampion, setIsChampion] = useState(false);
    const [pendingReviews, setPendingReviews] = useState(0);
    const [loading, setLoading] = useState(true);

    const [nextLesson, setNextLesson] = useState<{ id: string; title: string; module: string; order: number } | null>(null);

    useEffect(() => {
        async function loadIndicators() {
            if (!userId || !userForce) {
                setLoading(false);
                return;
            }

            const currentMonth = format(startOfMonth(new Date()), 'yyyy-MM-dd');

            try {
                // Parallel fetch of indicators AND canonical next lesson
                const [
                    xpRes,
                    rankRes,
                    champRes,
                    completedRes,
                    nextLessonRes
                ] = await Promise.all([
                    // 1. XP
                    supabase.from('mv_xp_mensal_recruta')
                        .select('xp_mensal')
                        .eq('user_id', userId).eq('force', userForce).eq('month_ref', currentMonth).maybeSingle(),
                    // 2. Ranking
                    supabase.from('mv_ranking_mensal')
                        .select('rank_position')
                        .eq('user_id', userId).eq('force', userForce).eq('month_ref', currentMonth).maybeSingle(),
                    // 3. Champion
                    supabase.from('mv_campeao_mensal')
                        .select('user_id')
                        .eq('force', userForce).eq('month_ref', currentMonth).maybeSingle(),
                    // 4. Completed Count
                    supabase.from('v_completed_lessons_count')
                        .select('completed_count')
                        .eq('user_id', userId).maybeSingle(),
                    // 5. Canonical Next Lesson (Server Side)
                    supabase.rpc('get_student_next_lesson', { p_user_id: userId }).maybeSingle()
                ]);

                // Set Indicators
                setXp(xpRes.data?.xp_mensal || 0);
                setRanking(rankRes.data?.rank_position || 0);
                setIsChampion(champRes.data?.user_id === userId);
                setCompleted(completedRes.data?.completed_count || 0);
                setPendingReviews(0);

                // Set Next Lesson from RPC
                if (nextLessonRes.data) {
                    setNextLesson({
                        id: nextLessonRes.data.lesson_id,
                        title: nextLessonRes.data.title,
                        module: nextLessonRes.data.module,
                        order: nextLessonRes.data.lesson_order
                    });
                } else {
                    // Logic handles 'completed course' implicit via null return + high completion count?
                    // For now, if null, we assume course start OR completed.
                    // If completed > 0 and no next lesson, likely completed.
                    if ((completedRes.data?.completed_count || 0) > 0) {
                        setNextLesson({
                            id: 'completed', // Marker
                            title: "Curso Concluído",
                            module: "Graduado",
                            order: 999
                        });
                    }
                }

            } catch (e) {
                console.error("Error fetching panel indicators", e);
            } finally {
                setLoading(false);
            }
        }

        loadIndicators();
    }, [userId, userForce]);

    return { xp, ranking, completed, isChampion, pendingReviews, nextLesson, loading };
}
