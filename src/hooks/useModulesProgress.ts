import { useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';

export interface ModuleProgress {
    module_id: string;
    module_title: string;
    total_lessons: number;
    completed_lessons: number;
    progress_percentage: number;
}

export function useModulesProgress() {
    const [modules, setModules] = useState<ModuleProgress[]>([]);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        let active = true;

        async function loadModules() {
            setLoading(true);

            try {
                // Using the CORRECT view: vw_recruta_module_progress_v2
                const { data, error } = await supabase
                    .from('vw_recruta_module_progress_v2')
                    .select('*');

                if (!active) return;

                if (error) {
                    throw error;
                } else {
                    setModules(data as any[] ?? []);
                }
            } catch (err) {
                console.error('[MODULES] Erro ao carregar módulos (Silencioso):', err);
                if (active) setModules([]);
            } finally {
                if (active) setLoading(false);
            }
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
