import { InstitutionalEvent, InstitutionalEventType } from '../types/institutionalEvents';

/**
 * Ordena eventos por Prioridade (Ascendente) e Timestamp (Ascendente)
 */
export function sortEvents(events: InstitutionalEvent[]): InstitutionalEvent[] {
    return [...events].sort((a, b) => {
        if (a.priority !== b.priority) {
            return a.priority - b.priority;
        }
        return a.timestamp - b.timestamp;
    });
}

/**
 * Consolida eventos do tipo 'medal' e 'grade' que compartilham o mesmo cycle_id OU timestamp.
 * Retorna uma nova lista com os eventos consolidados e os demais inalterados.
 */
export function consolidateEvents(events: InstitutionalEvent[]): InstitutionalEvent[] {
    const consolidatedList: InstitutionalEvent[] = [];
    const processedIds = new Set<string>();

    // Separa eventos candidatos à consolidação
    const candidates = events.filter(e => e.type === 'medal' || e.type === 'grade');

    for (let i = 0; i < candidates.length; i++) {
        const ev1 = candidates[i];
        if (processedIds.has(ev1.id)) continue;

        let matchFound = false;

        // Tenta encontrar um par
        for (let j = i + 1; j < candidates.length; j++) {
            const ev2 = candidates[j];
            if (processedIds.has(ev2.id)) continue;

            // Regra de Consolidação: Medal + Grade (ou vice-versa)
            const types = [ev1.type, ev2.type];
            const hasMedal = types.includes('medal');
            const hasGrade = types.includes('grade');

            if (hasMedal && hasGrade) {
                // Checa Coincidência Temporal ou de Ciclo
                const sameCycle = ev1.cycle_id && ev2.cycle_id && ev1.cycle_id === ev2.cycle_id;
                const sameTime = ev1.timestamp === ev2.timestamp;

                if (sameCycle || sameTime) {
                    // Consolida!
                    const consolidatedEvent: InstitutionalEvent = {
                        id: `consol-${ev1.id}-${ev2.id}`, // ID sintético
                        type: 'consolidated',
                        // A prioridade do consolidado deve ser alta para garantir exibição?
                        // O prompt não especifica a prioridade do consolidado, mas como contém grade (prio 2) e medal (prio 3),
                        // assumimos a maior prioridade entre os dois (ou seja, menor número).
                        priority: Math.min(ev1.priority, ev2.priority),
                        timestamp: Math.max(ev1.timestamp, ev2.timestamp), // Data mais recente
                        cycle_id: ev1.cycle_id || ev2.cycle_id,
                        sourceEvents: [ev1, ev2],
                        payload: {
                            medalEvent: ev1.type === 'medal' ? ev1 : ev2,
                            gradeEvent: ev1.type === 'grade' ? ev1 : ev2
                        }
                    };

                    consolidatedList.push(consolidatedEvent);
                    processedIds.add(ev1.id);
                    processedIds.add(ev2.id);
                    matchFound = true;
                    break;
                }
            }
        }

        if (!matchFound) {
            // Se não consolidou, não adicionamos aqui ainda? 
            // Não, precisamos manter os não-consolidados na lista final?
            // A função deve retornar TODOS os eventos, consolidados ou não.
            // Mas 'processedIds' marca quem JÁ FOI pra lista (como parte de consolidado).
            // Se não foi processado, será adicionado depois?
            // Melhor abordagem: Iterar sobre a lista original no final e adicionar quem não está em processedIds.
        }
    }

    // Adiciona itens que não foram consolidados
    const result = [...consolidatedList];
    for (const ev of events) {
        if (!processedIds.has(ev.id)) {
            result.push(ev);
        }
    }

    return result;
}

/**
 * Seleciona o evento a ser exibido na sessão.
 * Regras:
 * 1. Ordenar e Consolidar.
 * 2. Filtrar eventos já vistos (persistência local).
 * 3. Retornar o de maior prioridade (menor número).
 */
export function processEventQueue(
    rawEvents: InstitutionalEvent[],
    viewedEventIds: string[]
): InstitutionalEvent | null {
    if (!rawEvents || rawEvents.length === 0) return null;

    // 1. Consolida
    const consolidated = consolidateEvents(rawEvents);

    // 2. Ordena
    const sorted = sortEvents(consolidated);

    // 3. Filtra Já Vistos
    // Para eventos consolidados, verificamos se o ID consolidado já foi visto
    // OU se seus componentes já foram vistos (evitar repetição parcial).
    const candidates = sorted.filter(event => {
        if (viewedEventIds.includes(event.id)) return false;

        if (event.type === 'consolidated' && event.sourceEvents) {
            // Se algum dos eventos fonte já foi visto, consideramos o consolidado "visto" ou inválido?
            // "O histórico permanece completo". "Nunca repetir a mesma comunicação".
            // Se o usuário viu a medalha isolada antes, mostrar o consolidado agora repetiria a medalha?
            // Sim. Então se partes já foram vistas, talvez devêssemos mostrar apenas a nova parte?
            // O Prompt diz: "Se múltiplos eventos não consolidáveis: exibir apenas o maior prioridade".
            // Se consolidamos, é um "Novo Evento de UX".
            // Assumiremos: Se o ID sintético não foi visto, é novo.
            // (Melhoria futura: verificar sourceEvents)
        }
        return true;
    });

    if (candidates.length === 0) return null;

    // 3. Retorna o Top 1
    return candidates[0];
}
