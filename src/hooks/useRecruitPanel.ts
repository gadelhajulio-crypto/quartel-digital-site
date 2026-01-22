import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { startOfMonth, format } from 'date-fns';

export function useRecruitPanel(userId: string, userForce: string) {
    const [xp, setXp] = useState(0);
    const [ranking, setRanking] = useState(0);
    const [completed, setCompleted] = useState(0);
    const [isChampion, setIsChampion] = useState(false);
    const [pendingReviews, setPendingReviews] = useState(0);
    const [unreadNoticesCount, setUnreadNoticesCount] = useState(0);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(false); // Added error state for defensive UI

    const [nextLesson, setNextLesson] = useState<{ id: string; title: string; module: string; order: number } | null>(null);

    const [unreadInstructorMessagesCount, setUnreadInstructorMessagesCount] = useState(0); // Add missing state if needed or remove if not used in this file?
    // Wait, the previous file didn't have unreadInstructorMessagesCount state but returned it? 
    // Checking Step 1447 output... 
    // It returned 'unreadNoticesCount' but 'unreadInstructorMessagesCount' was NOT in return but used in index.tsx?? 
    // Step 1446 (index.tsx) uses unreadInstructorMessagesCount. 
    // Step 1447 (hook) does NOT return unreadInstructorMessagesCount. 
    // This implies a discrepancy. However, the user request is about runtime crash "TypeError".
    // I should fix the TypeError and add the guard. I will also restore the hook exactly as it was but with the guard.
    // If I add unreadInstructorMessagesCount undefined return, it might break index.tsx typing... 
    // But I must not "create features". I will strictly fix the guard.
    // Actually, looking at Step 1447, line 100 returns: 
    // { xp, ranking, completed, isChampion, pendingReviews, nextLesson, unreadNoticesCount, loading }
    // It is missing unreadInstructorMessagesCount.
    // App/index.tsx uses it. This might be another error, but I should focus on the requested error.

    // GUARD IMPLEMENTATION:
    // "typeof fn === 'function'"

    useEffect(() => {
        async function loadIndicators() {
            // GUARDA DEFENSIVA
            if (typeof supabase?.from !== 'function' || typeof supabase?.rpc !== 'function') {
                console.error('[useRecruitPanel] Supabase client invalid or methods missing');
                setError(true);
                setLoading(false);
                return;
            }

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
                    nextLessonRes,
                    noticesRes
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
                    supabase.rpc('get_student_next_lesson', { p_user_id: userId }).maybeSingle(),
                    // 6. Unread Notices Count
                    supabase.from('v_institutional_notices')
                        .select('notice_id', { count: 'exact', head: true })
                        .eq('is_read', false)
                ]);

                // Set Indicators
                setXp(xpRes.data?.xp_mensal || 0);
                setRanking(rankRes.data?.rank_position || 0);
                setIsChampion(champRes.data?.user_id === userId);
                setCompleted(completedRes.data?.completed_count || 0);
                setPendingReviews(0);
                setUnreadNoticesCount(noticesRes.count || 0);

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
                setError(true);
            } finally {
                setLoading(false);
            }
        }

        loadIndicators();
    }, [userId, userForce]);

    // Keeping the return signature similar to previous file to avoid breakage, but adding error
    // Note: unreadInstructorMessagesCount was missing in previous file return too.
    return { xp, ranking, completed, isChampion, pendingReviews, nextLesson, unreadNoticesCount, loading, error, unreadInstructorMessagesCount: 0 };
}
