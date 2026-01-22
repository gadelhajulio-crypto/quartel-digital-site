import { Lesson } from '../types/lesson';

export function isLessonBlocked(lesson: Lesson): boolean {
    if (!lesson) return true; // Safety check

    // 1. Apenas módulo RDM
    if (lesson.module !== 'regulamento-disciplinar-marinha') {
        return true;
    }

    // 2. Apenas as 3 primeiras aulas
    if (lesson.lesson_order > 3) {
        return true;
    }

    return false;
}
