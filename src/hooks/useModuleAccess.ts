// 1️⃣ Definições de Tipo Locais (Blindagem contra erros de import)
export interface Profile {
    id: string;
    tipo_acesso: 'degustacao' | 'completo' | 'admin';
    paid_at?: string | null;
    [key: string]: any;
}
export type Modulo = { id: string; titulo: string; is_degustacao: boolean; descricao?: string;[key: string]: any; };

// 2️⃣ Lógica de Controle de Acesso 
export const canAccessModule = ({ profile, modulo, }: { profile: Profile | null; modulo: Modulo; }): boolean => {
    // Se não estiver logado, bloqueia tudo 
    if (!profile) return false;

    // REGRA 1: Usuário Degustação -> Apenas módulos gratuitos 
    if (profile.tipo_acesso === 'degustacao') { return modulo.is_degustacao === true; }

    // REGRA 2: Usuário Completo/Pago 
    if (profile.tipo_acesso === 'completo') {
        // Se não tem data de pagamento (ex: inserido manual), libera total 
        if (!profile.paid_at) return true;

        const paidAt = new Date(profile.paid_at);
        const now = new Date();
        // Cálculo de dias desde a compra 
        const diferencaEmMilissegundos = now.getTime() - paidAt.getTime();
        const diasDesdePagamento = diferencaEmMilissegundos / (1000 * 60 * 60 * 24);

        // 🔒 BLOQUEIO ANTI-REEMBOLSO (7 Dias)
        // Se comprou há menos de 7 dias, mantém restrição de conteúdo
        if (diasDesdePagamento < 7) {
            return modulo.is_degustacao === true;
        }
        // Passou da garantia, libera tudo
        return true;
    }

    // Admin ou outros casos 
    return true;
};

// 3️⃣ Hook Helper para filtrar listas 
export function useModuleAccess(modules: Modulo[], profile: Profile | null) {
    if (!profile || !modules) return [];

    return modules.filter((modulo) => canAccessModule({ profile, modulo }));
}
