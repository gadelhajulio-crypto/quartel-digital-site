import { useState } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useAuth } from '../../src/context/AuthContext';
import { useBootstrapGate } from '../../src/context/BootstrapGateContext';
import { saveOnboardingData } from '../../src/services/onboardingService';
import { ObsidianScreen } from '../../src/design/layout/ObsidianScreen';
import { InstitutionalCard } from '../../src/design/components/InstitutionalCard';
import { InstitutionalButton } from '../../src/design/components/InstitutionalButton';
import { InstitutionalBadge } from '../../src/design/components/InstitutionalBadge';
import { InstitutionalSection } from '../../src/design/components/InstitutionalSection';
import { obsidiana } from '../../src/design/themes/obsidiana';
import { typographyPresets } from '../../src/design/tokens/typography';

const FORCA_LABELS: Record<string, string> = {
  exercito: 'Exército',
  marinha: 'Marinha',
  aeronautica: 'Aeronáutica',
};

export default function OnboardingConfirmacao() {
  const { forca, nome_guerra } = useLocalSearchParams<{ forca: string; nome_guerra: string }>();
  const { session, refetchProfile } = useAuth();
  const { retriggerGate } = useBootstrapGate();
  const router = useRouter();

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  console.log('[ONBOARDING_CONFIRM] render');
  console.log('[ONBOARDING_CONFIRM] selectedForca', forca ?? null);
  console.log('[ONBOARDING_CONFIRM] nomeGuerra', nome_guerra ? 'present' : 'absent');
  console.log('[ONBOARDING_CONFIRM] loading', loading);

  async function handleConfirm() {
    console.log('[ONBOARDING_CONFIRM] button_pressed');
    console.log('[ONBOARDING_CONFIRM] validate_start');

    if (!forca) {
      console.log('[ONBOARDING_CONFIRM] blocked_missing_forca');
      return;
    }

    if (!nome_guerra) {
      console.log('[ONBOARDING_CONFIRM] blocked_missing_nome');
      return;
    }

    if (loading) {
      console.log('[ONBOARDING_CONFIRM] blocked_loading');
      return;
    }

    if (!session) {
      console.log('[ONBOARDING_CONFIRM] blocked_missing_session');
      setError('Sessão expirada. Faça login novamente.');
      return;
    }

    setLoading(true);
    setError(null);

    try {
      console.log('[ONBOARDING_CONFIRM] rpc_start');

      // rpc_complete_onboarding usa auth.uid() internamente — param _recrutaId ignorado
      // TODO Sprint 4: substituir session.user.id por profile?.id (recrutas.id)
      await saveOnboardingData(session.user.id, forca as any, nome_guerra);

      console.log('[ONBOARDING_CONFIRM] rpc_success');

      await refetchProfile();
      retriggerGate();
    } catch (err: any) {
      console.log('[ONBOARDING_CONFIRM] rpc_error', { message: err?.message ?? 'unknown' });
      setError('Não foi possível registrar. Verifique sua conexão e tente novamente.');
    } finally {
      console.log('[ONBOARDING_CONFIRM] finalize');
      setLoading(false);
    }
  }

  function handleAlterar() {
    router.replace('/(onboarding)/welcome' as any);
  }

  return (
    <ObsidianScreen scrollable>
      <View style={styles.inner}>
        {/* PASSO */}
        <InstitutionalBadge
          theme={obsidiana}
          label="Passo 3 de 3"
          variant="muted"
          style={styles.stepBadge}
        />

        {/* CABEÇALHO */}
        <View style={styles.heading}>
          <Text
            style={[
              typographyPresets.sectionTitle,
              { color: obsidiana.colors.accent, textAlign: 'center' },
            ]}
          >
            Confirme sua{'\n'}identidade funcional.
          </Text>
          <Text style={[typographyPresets.body, styles.subtitle]}>
            Revise as informações antes de registrar seu vínculo.
          </Text>
        </View>

        {/* CARD DE REVISÃO */}
        <InstitutionalCard theme={obsidiana} elevated style={styles.card}>
          <InstitutionalSection title="Identidade registrada" theme={obsidiana}>
            <View style={styles.dataRow}>
              <Text style={[typographyPresets.label, { color: obsidiana.colors.muted }]}>
                Força
              </Text>
              <Text style={[typographyPresets.cardTitle, { color: obsidiana.colors.text }]}>
                {FORCA_LABELS[forca] ?? forca}
              </Text>
            </View>

            <View
              style={[styles.rowDivider, { backgroundColor: obsidiana.colors.border }]}
            />

            <View style={styles.dataRow}>
              <Text style={[typographyPresets.label, { color: obsidiana.colors.muted }]}>
                Nome de guerra
              </Text>
              <Text
                style={[
                  typographyPresets.cardTitle,
                  { color: obsidiana.colors.accent, letterSpacing: 2 },
                ]}
              >
                {nome_guerra}
              </Text>
            </View>
          </InstitutionalSection>
        </InstitutionalCard>

        {/* ERRO */}
        {error && (
          <InstitutionalBadge
            theme={obsidiana}
            label={error}
            variant="error"
            style={styles.errorBadge}
          />
        )}

        {/* CONFIRMAR */}
        <InstitutionalButton
          theme={obsidiana}
          label="Confirmar vínculo institucional"
          onPress={handleConfirm}
          loading={loading}
          disabled={loading}
          size="l"
          style={styles.button}
        />

        {/* ALTERAR DADOS */}
        <InstitutionalButton
          theme={obsidiana}
          label="Alterar dados"
          onPress={handleAlterar}
          disabled={loading}
          size="l"
          variant="secondary"
          style={styles.button}
        />

        {/* AVISO */}
        <Text style={[typographyPresets.label, styles.disclaimer]}>
          Esta ação registra seu vínculo institucional e não pode ser desfeita.
        </Text>
      </View>
    </ObsidianScreen>
  );
}

const styles = StyleSheet.create({
  inner: {
    flex: 1,
    paddingVertical: 8,
  },
  stepBadge: {
    alignSelf: 'center',
    marginBottom: 24,
  },
  heading: {
    alignItems: 'center',
    marginBottom: 32,
    gap: 10,
  },
  subtitle: {
    color: obsidiana.colors.textSecondary,
    textAlign: 'center',
    paddingHorizontal: 16,
  },
  card: {
    marginBottom: 24,
  },
  dataRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 10,
  },
  rowDivider: {
    height: 1,
  },
  errorBadge: {
    alignSelf: 'stretch',
    marginBottom: 16,
  },
  button: {
    marginBottom: 16,
  },
  disclaimer: {
    color: obsidiana.colors.muted,
    textAlign: 'center',
  },
});
