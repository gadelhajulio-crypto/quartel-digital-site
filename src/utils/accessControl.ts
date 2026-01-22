export const isLessonBlocked = (lesson: any) => {
    // 1. Apenas o módulo RDM é liberado para degustação
    if (lesson.module !== 'regulamento-disciplinar-marinha') {
        return true; // Bloqueia tudo de outros módulos
    }

    // 2. No módulo RDM, apenas as 3 primeiras aulas (ordem 1, 2, 3)
    return lesson.lesson_order > 3;
};

export const isReviewAvailable = (completedAt: string | null, delayHours: number) => {
    if (!completedAt) return false;
    const completedDate = new Date(completedAt);
    const now = new Date();
    const diffHours = (now.getTime() - completedDate.getTime()) / (1000 * 60 * 60);
    return diffHours >= delayHours;
};
