import { supabase } from '../lib/supabase';

export const fetchLessons = async () => {
    const { data, error } = await supabase
        .from('v_lessons_panel')
        .select('*')
        // View includes force column, we could filter or rely on view logic. 
        // Prompt says: "Query no APP ... select('*').order(...)". 
        // It doesn't show .eq('force', 'marinha'). 
        // But the view selects ALL from lessons. 
        // If the app is multi-force, we might need filtering. 
        // The user prompt in step 0 said: "A query deve buscar tudo da força Marinha".
        // I will keep the filter unless the view is already filtered (definition showed `select ... from lessons l`, no where clause).
        // So I should keep the filter.
        .eq('force', 'marinha')
        .order('module')
        .order('lesson_order');

    // Compatibility: Map lesson_id to id for existing components
    const mappedData = data?.map((item: any) => ({
        ...item,
        id: item.lesson_id
    }));

    return { data: mappedData, error };
};

export const fetchLessonById = async (id: string) => {
    return await supabase
        .from('v_lessons_panel')
        .select('*')
        .eq('lesson_id', id)
        .maybeSingle();
};
