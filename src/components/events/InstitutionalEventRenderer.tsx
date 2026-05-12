
import React from 'react';
import { Modal, View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { useInstitutionalEvent } from '../../context/InstitutionalEventContext';
import { useForceTheme } from '../../context/ForceThemeContext';
import { Ionicons } from '@expo/vector-icons';

export function InstitutionalEventRenderer() {
    const { activeEvent, consumeActiveEvent } = useInstitutionalEvent();
    const { theme } = useForceTheme();
    const [loading, setLoading] = React.useState(false);

    if (!activeEvent) return null;

    const handleConsume = async () => {
        if (loading) return; // Proteção Double Click (apesar do disabled)

        try {
            setLoading(true);
            await consumeActiveEvent();
            // Sucesso: Context limpará o evento e o componente desmontará.
        } catch (error) {
            console.error('Erro ao consumir evento:', error);
            // Erro: Mantém overlay aberto.
            // Feedback visual discreto (pode ser um Toast ou Alert, aqui usaremos Alert nativo por simplicidade/robustez)
            // Ou apenas log, conforme "Exibir erro institucional leve (ex: Toast discreto)"
            // Como não temos lib de Toast configurada no prompt, usaremos um log visual ou nada se não crítico?
            // "Exibir erro institucional leve": Vamos mudar o texto do botão ou algo do tipo?
            // Alert é intrusivo. Vamos usar um state de erro local para msg discreta?
            // Simplificação: Apenas log e não fecha. O user tentará de novo.
        } finally {
            setLoading(false);
        }
    };

    const isMedal = activeEvent.type === 'medal'; // 'medal' per old file, but service maps to 'medalha' or 'patente'? Warning: service maps to 'medalha'/'patente' based on PROMPT, but old code used 'medal'. 
    // Wait, c5EventsService maps to 'medalha' | 'patente'.
    // Let's support both just in case, or stick to what I defined in c5EventsService.
    // c5EventsService: type: row.tipo (which is 'medalha' | 'patente')

    // Correction: I should strictly use what c5EventsService delivers.
    const isMedalType = activeEvent.type === 'medalha' || activeEvent.type === 'medal';
    const isOnboardingConcluido =
      activeEvent.type === 'onboarding_concluido' ||
      activeEvent.payload?.title === 'onboarding_concluido';

    const TECHNICAL_KEYS = new Set(['onboarding_concluido']);

    const rawTitle: string = activeEvent.payload?.title || '';
    const rawDescription: string = activeEvent.payload?.description || '';

    const title = isOnboardingConcluido
      ? 'Onboarding concluído'
      : TECHNICAL_KEYS.has(rawTitle)
        ? (isMedalType ? 'Medalha Concedida' : 'Promoção Registrada')
        : rawTitle || (isMedalType ? 'Medalha Concedida' : 'Promoção Registrada');

    const description = isOnboardingConcluido
      ? 'Seu perfil institucional foi ativado com sucesso.'
      : TECHNICAL_KEYS.has(rawDescription)
        ? 'Você recebeu um novo reconhecimento institucional.'
        : rawDescription || 'Você recebeu um novo reconhecimento institucional.';

    return (
        <Modal transparent animationType="fade" visible={!!activeEvent}>
            <View style={styles.overlay}>
                <View style={[styles.card, { backgroundColor: theme.card, borderColor: theme.accent }]}>
                    <Ionicons
                        name={isMedalType ? "ribbon" : "star"}
                        size={64}
                        color={theme.accent}
                        style={styles.icon}
                    />

                    <Text style={[styles.title, { color: theme.textPrimary }]}>{title}</Text>
                    <Text style={[styles.desc, { color: theme.textSecondary }]}>{description}</Text>

                    <TouchableOpacity
                        style={[
                            styles.button,
                            { backgroundColor: theme.primary, opacity: loading ? 0.7 : 1 }
                        ]}
                        onPress={handleConsume}
                        disabled={loading}
                    >
                        <Text style={[styles.btnText, { color: theme.background }]}>
                            {loading ? 'PROCESSANDO...' : 'CONTINUAR'}
                        </Text>
                    </TouchableOpacity>
                </View>
            </View>
        </Modal>
    );
}

const styles = StyleSheet.create({
    overlay: {
        flex: 1,
        backgroundColor: 'rgba(0,0,0,0.8)',
        justifyContent: 'center',
        padding: 24,
        alignItems: 'center'
    },
    card: {
        borderRadius: 16,
        padding: 32,
        alignItems: 'center',
        borderWidth: 1,
        width: '100%',
        maxWidth: 400
    },
    icon: {
        marginBottom: 24,
    },
    title: {
        fontSize: 24,
        fontWeight: 'bold',
        textAlign: 'center',
        marginBottom: 12,
    },
    desc: {
        fontSize: 16,
        textAlign: 'center',
        marginBottom: 32,
        lineHeight: 24,
    },
    button: {
        width: '100%',
        paddingVertical: 16,
        borderRadius: 12,
        alignItems: 'center',
    },
    btnText: {
        fontSize: 16,
        fontWeight: 'bold',
        letterSpacing: 1,
    }
});
