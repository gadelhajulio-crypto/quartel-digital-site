export type NextLesson = {
    lesson_id: string;
    title: string;
    module: string;
    lesson_order: number;
    status: 'available' | 'completed' | 'blocked';
};

// Hook NEUTRALIZADO para build de teste
// Retorna sempre null e loading false para forçar navegação ao Painel
export function useNextLesson(userId?: string) {
    // Retorno imediato, sem efeitos, sem promises
    return {
        nextLesson: null,
        loading: false,
        error: null
    };
}
