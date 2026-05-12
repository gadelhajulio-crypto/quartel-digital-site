export type InstitutionalEventType = 'medal' | 'grade' | 'consolidated' | 'medalha' | 'patente' | 'onboarding_concluido';

export interface InstitutionalEvent {
    id: string;
    type: InstitutionalEventType;
    priority: number;
    timestamp: number;
    cycle_id?: string;
    // Payload opcional para dados específicos (ex: detalhes da medalha/promoção)
    payload?: any;
    // Flag para identificar eventos que foram consolidados (para fins de histórico/debug se necessário)
    sourceEvents?: InstitutionalEvent[];
}

export const EVENT_PRIORITIES = {
    GRADE_6: 1,
    GRADE_PROMOTION: 2,
    MEDAL: 3,
    OTHER: 4
};
