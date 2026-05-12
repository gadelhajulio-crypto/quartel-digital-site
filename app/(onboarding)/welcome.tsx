import { useState } from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { ObsidianScreen } from '../../src/design/layout/ObsidianScreen';
import { InstitutionalCard } from '../../src/design/components/InstitutionalCard';
import { InstitutionalButton } from '../../src/design/components/InstitutionalButton';
import { InstitutionalBadge } from '../../src/design/components/InstitutionalBadge';
import { InstitutionalSection } from '../../src/design/components/InstitutionalSection';
import { obsidiana } from '../../src/design/themes/obsidiana';
import { typographyPresets } from '../../src/design/tokens/typography';

type Forca = 'marinha' | 'exercito' | 'aeronautica';

type ForcaOption = {
  label: string;
  value: Forca;
  sigla: string;
  descricao: string;
  accentColor: string;
};

const FORCAS: ForcaOption[] = [
  {
    label: 'Marinha',
    value: 'marinha',
    sigla: 'MB',
    descricao: 'Marinha do Brasil',
    accentColor: '#1a6498',
  },
  {
    label: 'Exército',
    value: 'exercito',
    sigla: 'EB',
    descricao: 'Exército Brasileiro',
    accentColor: '#1e5c20',
  },
  {
    label: 'Aeronáutica',
    value: 'aeronautica',
    sigla: 'FAB',
    descricao: 'Força Aérea Brasileira',
    accentColor: '#003a8f',
  },
];

export default function OnboardingForca() {
  const router = useRouter();
  const [selected, setSelected] = useState<Forca | null>(null);

  function confirmar() {
    if (!selected) return;
    router.push({ pathname: '/(onboarding)/nome-guerra', params: { forca: selected } });
  }

  return (
    <ObsidianScreen scrollable>
      <View style={styles.inner}>
        {/* PASSO */}
        <InstitutionalBadge
          theme={obsidiana}
          label="Passo 1 de 3"
          variant="muted"
          style={styles.stepBadge}
        />

        {/* CABEÇALHO */}
        <View style={styles.heading}>
          <Text style={[typographyPresets.sectionTitle, { color: obsidiana.colors.accent, textAlign: 'center' }]}>
            Selecione sua força{'\n'}institucional.
          </Text>
          <Text style={[typographyPresets.body, styles.subtitle]}>
            Esta definição será registrada em sua identidade funcional.
          </Text>
        </View>

        {/* OPÇÕES DE FORÇA */}
        <InstitutionalSection theme={obsidiana} style={styles.section}>
          {FORCAS.map((forca) => {
            const isSelected = selected === forca.value;
            return (
              <TouchableOpacity
                key={forca.value}
                activeOpacity={0.8}
                onPress={() => setSelected(forca.value)}
              >
                <InstitutionalCard
                  theme={obsidiana}
                  accent={isSelected}
                  style={[
                    styles.forcaCard,
                    isSelected && {
                      borderColor: forca.accentColor,
                      borderWidth: 2,
                    },
                  ]}
                >
                  <View style={styles.forcaRow}>
                    {/* SIGLA */}
                    <View
                      style={[
                        styles.siglaBadge,
                        { backgroundColor: forca.accentColor + '22' },
                      ]}
                    >
                      <Text style={[styles.siglaText, { color: forca.accentColor }]}>
                        {forca.sigla}
                      </Text>
                    </View>

                    {/* TEXTO */}
                    <View style={styles.forcaInfo}>
                      <Text
                        style={[
                          typographyPresets.cardTitle,
                          { color: isSelected ? forca.accentColor : obsidiana.colors.text },
                        ]}
                      >
                        {forca.label}
                      </Text>
                      <Text
                        style={[
                          typographyPresets.bodySmall,
                          { color: obsidiana.colors.muted, marginTop: 2 },
                        ]}
                      >
                        {forca.descricao}
                      </Text>
                    </View>

                    {/* INDICADOR */}
                    {isSelected && (
                      <View
                        style={[
                          styles.indicator,
                          { borderColor: forca.accentColor, backgroundColor: forca.accentColor },
                        ]}
                      />
                    )}
                    {!isSelected && (
                      <View style={[styles.indicator, { borderColor: obsidiana.colors.border }]} />
                    )}
                  </View>
                </InstitutionalCard>
              </TouchableOpacity>
            );
          })}
        </InstitutionalSection>

        {/* BOTÃO CONFIRMAR */}
        <InstitutionalButton
          theme={obsidiana}
          label="Confirmar vínculo institucional"
          onPress={confirmar}
          disabled={!selected}
          size="l"
          style={styles.confirmButton}
        />
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
  section: {
    marginBottom: 24,
  },
  forcaCard: {
    marginBottom: 12,
  },
  forcaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
  },
  siglaBadge: {
    width: 52,
    height: 52,
    borderRadius: 8,
    alignItems: 'center',
    justifyContent: 'center',
  },
  siglaText: {
    fontSize: 15,
    fontWeight: '700',
    letterSpacing: 1,
  },
  forcaInfo: {
    flex: 1,
  },
  indicator: {
    width: 20,
    height: 20,
    borderRadius: 10,
    borderWidth: 2,
  },
  confirmButton: {
    marginTop: 8,
  },
});
