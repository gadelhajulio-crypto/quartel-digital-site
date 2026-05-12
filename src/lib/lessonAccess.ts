import { Lesson } from '../types/lesson';

export function isLessonBlocked(lesson: Lesson): boolean {
    if (!lesson) return true; // Safety check

    // C2 FIX: Controle de acesso é feito no nível do Módulo ou via Rules Engine do Supabase.
    // O frontend não deve bloquear com strings hardcoded.
    return false;
}
