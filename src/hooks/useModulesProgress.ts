import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

export interface ModuleProgress {
    module_id: string;
    module_name: string;
    total_lessons: number;
    completed_lessons: number;
    progress_percent: number;
}

export function useModulesProgress() {
    const [modules, setModules] = useState<ModuleProgress[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        let active = true;

        async function loadModules() {
            setLoading(true);

            const { data, error } = await supabase
                .from('v_modules_progress') // view pronta no backend
                .select('*')
                .order('module_order');

            if (!active) return;

            if (error) {
                console.error('[MODULES] Erro ao carregar módulos:', error);
                setModules([]);
            } else {
                setModules(data ?? []);
            }

            setLoading(false);
        }

        loadModules();

        return () => {
            active = false;
        };
    }, []);

    return {
        modules,
        loading,
    };
}
