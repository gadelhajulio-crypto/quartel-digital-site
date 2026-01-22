import { Profile } from '../context/AuthContext';

/**
 * Verifica se o usuário pode acessar um módulo específico.
 * Mantido para compatibilidade.
 * @param moduleId - ID do módulo
 * @param profile - Perfil do usuário
 * @returns true se tiver acesso
 */
export const canAccessModule = (moduleId: string | number, profile: Profile | null): boolean => {
    if (!profile) return false;

    if (profile.tipo_acesso === 'completo') return true;

    if (profile.tipo_acesso === 'degustacao') {
        const id = typeof moduleId === 'string' ? parseInt(moduleId, 10) : moduleId;
        return id === 1 || id === 2;
    }

    return false;
};

/**
 * Verifica se o usuário pode acessar uma revisão específica.
 * @param reviewId - ID da revisão
 * @param moduleId - ID do módulo
 * @param profile - Perfil do usuário
 * @returns true se tiver acesso
 */
export const canAccessReview = (reviewId: string | number, moduleId: string | number, profile: Profile | null): boolean => {
    // Primeiro valida se pode acessar o módulo
    if (!canAccessModule(moduleId, profile)) return false;

    if (profile?.tipo_acesso === 'completo') return true;

    if (profile?.tipo_acesso === 'degustacao') {
        const rId = typeof reviewId === 'string' ? parseInt(reviewId, 10) : reviewId;
        return rId === 1;
    }

    return false;
};

/**
 * Verifica se o módulo está desbloqueado baseado no nível do usuário.
 * @param moduleId - ID do módulo
 * @param profile - Perfil do usuário
 * @returns true se desbloqueado
 */
export const isModuleUnlockedByLevel = (moduleId: string | number, profile: Profile | null): boolean => {
    if (!profile) return false;

    const userLevel = profile.nivel_atual ? parseInt(String(profile.nivel_atual), 10) : 1;
    const moduleNumber = typeof moduleId === 'string' ? parseInt(moduleId, 10) : moduleId;

    return userLevel >= moduleNumber;
};

/**
 * Retorna lista de IDs de módulos acessíveis.
 * @param profile - Perfil do usuário
 * @returns Array de IDs dos módulos
 */
export const getAccessibleModules = (profile: Profile | null): number[] => {
    if (!profile) return [];

    if (profile.tipo_acesso === 'completo') {
        // Retorna array de 1 a 20
        return Array.from({ length: 20 }, (_, i) => i + 1);
    }

    if (profile.tipo_acesso === 'degustacao') {
        return [1, 2];
    }

    return [];
};
