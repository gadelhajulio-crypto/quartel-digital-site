import { useState, useEffect } from 'react';
import { isReviewAvailable } from '../utils/accessControl';

export function useLessonMedia(lesson: any, lessonProgress: any) {
    const [canReview, setCanReview] = useState(false);

    useEffect(() => {
        if (!lesson || !lessonProgress?.completed_at) {
            setCanReview(false);
            return;
        }

        // Delay de 24 horas para revisão
        const available = isReviewAvailable(lessonProgress.completed_at, 24);
        setCanReview(available);
    }, [lesson, lessonProgress]);

    return { canReview };
}
