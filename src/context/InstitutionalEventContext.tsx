import React, { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { InstitutionalEvent } from '../types/institutionalEvents';
import { listPendingEvents, consumeEvent } from '../services/c5EventsService';
import { processEventQueue } from '../services/institutionalEventService';

interface InstitutionalEventContextData {
    activeEvent: InstitutionalEvent | null;
    consumeActiveEvent: () => Promise<void>;
    isLoading: boolean;
    error: boolean;
    loadEvents: () => void;
}

const InstitutionalEventContext = createContext<InstitutionalEventContextData>({} as InstitutionalEventContextData);

export function InstitutionalEventProvider({ children }: { children: ReactNode }) {
    const [activeEvent, setActiveEvent] = useState<InstitutionalEvent | null>(null);
    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState(false);
    const [sessionShown, setSessionShown] = useState(false);

    // Carrega eventos ao iniciar a sessão (mount)
    useEffect(() => {
        loadEvents();
    }, []);

    async function loadEvents() {
        try {
            setIsLoading(true);
            setError(false);

            // Regra: Apenas 1 tela por sessão
            if (sessionShown) {
                return;
            }

            // Busca eventos pendentes do backend (View C5)
            const pendingEvents = await listPendingEvents();

            // Processa fila (ordenação e consolidação)
            // Nota: processEventQueue espera viewedIds, mas agora o backend define o que é pendente.
            // Passamos array vazio pois a view já filtra o que foi consumido.
            const next = processEventQueue(pendingEvents, []);

            if (next) {
                setActiveEvent(next);
            }
        } catch (e) {
            console.error('Failed to load institutional events', e);
            setError(true);
        } finally {
            setIsLoading(false);
        }
    }

    // Renamed to be semantic: this consumes the event.
    async function consumeActiveEvent(): Promise<void> {
        if (activeEvent) {
            if (!activeEvent.id) {
                // ETAPA 1 - Guard explícito contra erro PGRST202 (consumir_evento sem parâmetro)
                const error = new Error('Evento institucional sem id válido para consumo.');
                console.error('[C5] Tentativa de consumo de evento sem ID', activeEvent);
                throw error;
            }

            try {
                // 1. Consumo Real (RPC) - Wait for it!
                await consumeEvent(activeEvent.id);

                // 2. Só limpa se sucesso
                setActiveEvent(null);
                setSessionShown(true); // Marca sessão como "queimada"
            } catch (e) {
                console.error('Failed to consume event', e);
                // 3. Em erro: NÃO limpa activeEvent.
                // Re-throw para que o componente saiba que falhou e mantenha o modal aberto.
                throw e;
            }
        }
    }

    return (
        <InstitutionalEventContext.Provider value={{
            activeEvent,
            consumeActiveEvent,
            isLoading,
            error,
            loadEvents
        }}>
            {children}
        </InstitutionalEventContext.Provider>
    );
}

export function useInstitutionalEvent() {
    const context = useContext(InstitutionalEventContext);
    if (!context) {
        throw new Error('useInstitutionalEvent must be used within an InstitutionalEventProvider');
    }
    return context;
}
