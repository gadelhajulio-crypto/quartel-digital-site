import { supabase } from '../lib/supabase';
import { InstitutionalEvent, InstitutionalEventType } from '../types/institutionalEvents';

/**
 * Serviço C5 - Camada de Eventos Institucionais (Backend Driven)
 * Contrato Rigoroso:
 * - View: v_eventos_pendentes
 * - RPC: consumir_evento_c5
 */

interface C5EventRow {
    id: string;
    recruta_id?: string;
    tipo: string;
    referencia_id?: string;
    titulo: string;
    descricao: string;
    prioridade: number;
    cycle_id?: string;
    emitido_em: string;
    processado?: boolean;
}

export async function listPendingEvents(): Promise<InstitutionalEvent[]> {
    const { data, error } = await supabase
        .from('v_eventos_pendentes')
        .select('*');

    if (error) {
        console.error('C5 Service Error (listPendingEvents):', error);
        throw error;
    }

    if (!data) return [];

    // Filtra eventos de autenticação que representam "security_logout"
    // Regra oficial: não abrir modal. A comunicação desse evento é feita apenas via banner no login.
    const validData = data
        .map((row: C5EventRow) => {
            // ETAPA 2 - Hardening do Mapeamento: assegurar ID oficial
            const eventId = row.id;
            if (!eventId) return null;

            // Retorna row validada sem dependência de payload estrutural
            return {
                ...row,
                id: eventId,
            };
        })
        .filter(Boolean) as C5EventRow[];

    const filteredData = validData.filter((row: C5EventRow) => {
        // Detecta security_logout pelos campos literais sem payload
        return row.tipo !== 'security_logout' && row.referencia_id !== 'security_logout';
    });

    // Mapeamento DB -> App Type
    return filteredData.map((row: C5EventRow) => ({
        id: row.id,
        type: row.tipo as InstitutionalEventType, // 'medalha' | 'patente' (assumindo compatibilidade)
        priority: row.prioridade,
        timestamp: new Date(row.emitido_em).getTime(),
        cycle_id: row.cycle_id,
        // Constrói payload interno apenas com dados estruturados da view
        payload: {
            title: row.titulo,
            description: row.descricao,
            referenceId: row.referencia_id
        }
    }));
}

export async function consumeEvent(eventId: string): Promise<void> {
    const { error } = await supabase.rpc('consumir_evento_c5', {
        p_evento_id: eventId
    });

    if (error) {
        // C5_WRITE_BLOCKED é um erro esperado de regra de negócio, mas aqui tratamos como erro técnico
        // Se o backend bloquear, é porque já foi consumido ou erro de permissão.
        console.error('C5 Service Error (consumeEvent):', error);
        throw error;
    }
}
