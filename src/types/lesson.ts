export interface LessonMedia {
    id: string;
    type: 'video' | 'pdf' | 'audio';
    url: string;
}

export interface LessonProgress {
    completed_at: string | null;
    user_id?: string;
}

export interface Lesson {
    id: string;
    title: string;
    module: string;
    lesson_order: number;
    lesson_media?: LessonMedia[];
    lesson_progress?: LessonProgress;
    force?: string; // from previous context
}
