import { supabase } from '../lib/supabase';

export const registerXp = async (amount: number, description: string, sourceId?: string) => {
    try {
        const { data, error } = await supabase.rpc('registrar_xp', {
            p_amount: amount,
            p_description: description,
            p_source_id: sourceId
        });

        if (error) {
            console.error('[XP] Error registering XP:', error);
            return null;
        }

        return data; // Returns new total
    } catch (err) {
        console.error('[XP] Exception registering XP:', err);
        return null;
    }
};
