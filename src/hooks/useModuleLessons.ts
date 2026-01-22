import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { LessonStatus } from '../components/rows/LessonRow';

export interface ModuleLesson {
    lesson_id: string;
    lesson_order: number;
    lesson_title: string;
    status: LessonStatus;
}

export function useModuleLessons(moduleId: string) {
    const [lessons, setLessons] = useState<ModuleLesson[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        let active = true;

        async function loadLessons() {
            setLoading(true);

            const { data, error } = await supabase
                .from('v_module_lessons') // view pronta no backend
                .select('*')
                .eq('module_id', moduleId)
                .order('lesson_order');

            if (!active) return;

            if (error) {
                console.error('[MODULE LESSONS] Erro ao carregar aulas:', error);
                setLessons([]);
            } else {
                setLessons(data ?? []);
            }

            setLoading(false);
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
