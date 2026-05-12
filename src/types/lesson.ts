export interface LessonProgress {
    completed_at: string | null;
    user_id?: string;
}

// Reflete v_lessons_panel (contrato C6)
export interface Lesson {
    lesson_id: string;
    title: string;
    module: string;
    lesson_order: number;
    force?: string;
    video_url: string | null;
    pdf_url: string | null;
    completed_at?: string | null;
}
