import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { LessonStatus } from '../components/rows/LessonRow';

export interface ModuleLesson {
    lesson_id: string;
    lesson_order: number;
    lesson_title: string;
    status: LessonStatus;
    module_id: string;
    module_title: string;
    forca: string;
    is_degustacao: boolean;
    video_url: string | null;
    pdf_url: string | null;
}

export function useModuleLessons(moduleId: string) {
    const [lessons, setLessons] = useState<ModuleLesson[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        let active = true;

        async function loadLessons() {
            setLoading(true);

            try {
                // View canônica: vw_rdm_lessons_v2 — filtro por module_id
                const { data, error } = await supabase
                    .from('vw_rdm_lessons_v2')
                    .select('*')
                    .eq('module_id', moduleId)
                    .order('lesson_order');

                if (!active) return;

                if (error) throw error;

                setLessons((data as ModuleLesson[]) ?? []);
            } catch (err) {
                console.error('[MODULE LESSONS] Erro ao carregar aulas (Silencioso):', err);
                if (active) setLessons([]);
            } finally {
                if (active) setLoading(false);
            }
        }

        if (moduleId) {
            loadLessons();
        }

        return () => {
            active = false;
        };
    }, [moduleId]);

    return {
        lessons,
        loading,
    };
}
