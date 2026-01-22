import { supabase } from '../lib/supabase';
import { Profile } from '../context/AuthContext';
import { User } from '@supabase/supabase-js';

export interface ChatMessagePayload {
    message: string;
    context: {
        user_id: string;
        recruta_id: string;
        force: string;
        access_mode: string;
        instructor_profile_id: string;
    };
}

export interface ChatResponse {
    reply: string;
}

export async function sendChatMessage(
    text: string,
    user: User | null,
    profile: Profile | null
): Promise<ChatResponse> {

    // 1. VALIDATION (Fallback Security)
    if (!text.trim()) {
        throw new Error('Mensagem vazia não pode ser enviada.');
    }

    if (!user || !profile) {
        console.error('[ChatService] Bloqueio: Usuário ou Perfil não carregados.');
        throw new Error('Identidade do recruta não identificada. Tente reiniciar o app.');
    }

    if (!profile.forca || !profile.instructor_profile_id) {
        console.error('[ChatService] Bloqueio: Dados críticos do perfil ausentes.', profile);
        throw new Error('Perfil incompleto. Contate o suporte.');
    }

    // 2. PAYLOAD ASSEMBLY (Centralized & Immutable)
    // Derived access mode
    const accessMode = profile.tipo_acesso === 'completo' ? 'full_access' : 'restricted';

    const payload: ChatMessagePayload = {
        message: text,
        context: {
            user_id: user.id,
            recruta_id: profile.id, // Usually same as user_id, but explicit
            force: profile.forca,
            access_mode: accessMode, // Standardized value
            instructor_profile_id: profile.instructor_profile_id,
        }
    };

    console.log('[ChatService] Enviando payload padronizado:', JSON.stringify(payload, null, 2));

    // 3. SEND (Single Point of Exit)
    try {
        const { data, error } = await supabase.functions.invoke('instrutor-send', {
            body: payload
        });

        if (error) {
            console.error('[ChatService] Erro no envio:', error);
            throw error;
        }

        return data;

    } catch (err) {
        console.error('[ChatService] Exceção crítica:', err);
        throw err;
    }
}
