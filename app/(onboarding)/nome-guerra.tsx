import { useState } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { ObsidianScreen } from '../../src/design/layout/ObsidianScreen';
import { InstitutionalInput } from '../../src/design/components/InstitutionalInput';
import { InstitutionalButton } from '../../src/design/components/InstitutionalButton';
import { InstitutionalBadge } from '../../src/design/components/InstitutionalBadge';
import { obsidiana } from '../../src/design/themes/obsidiana';
import { typographyPresets } from '../../src/design/tokens/typography';
import { spacing } from '../../src/design/tokens/spacing';

export default function OnboardingNomeGuerra() {
  const router = useRouter();
  const { forca } = useLocalSearchParams<{ forca: string }>();
  const [nomeGuerra, setNomeGuerra] = useState('');

  function avancar() {
    const nome = nomeGuerra.trim();
    if (!nome) return;
    router.push({
      pathname: '/(onboarding)/confirmacao',
      params: { forca, nome_guerra: nome },
    });
  }

  return (
    <ObsidianScreen avoidKeyboard>
      <View style={styles.inner}>
        {/* PASSO */}
        <InstitutionalBadge
          theme={obsidiana}
          label="Passo 2 de 3"
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
            Defina seu{'\n'}nome de guerra.
          </Text>
          <Text
            style={[
              typographyPresets.body,
              { color: obsidiana.colors.textSecondary, textAlign: 'center' },
            ]}
          >
            Será exibido em rankings, missões e comunicações institucionais.
          </Text>
        </View>

        {/* CAMPO */}
        <InstitutionalInput
          theme={obsidiana}
          label="Nome de guerra"
          placeholder="Ex: SILVA"
          value={nomeGuerra}
          onChangeText={setNomeGuerra}
          autoCapitalize="characters"
          returnKeyType="done"
          onSubmitEditing={avancar}
          containerStyle={styles.input}
          style={{ textAlign: 'center', letterSpacing: 3, fontSize: 20 }}
        />

        {/* BOTÃO */}
        <InstitutionalButton
          theme={obsidiana}
          label="Continuar"
          onPress={avancar}
          disabled={!nomeGuerra.trim()}
          size="l"
        />
      </View>
    </ObsidianScreen>
  );
}

const styles = StyleSheet.create({
  inner: {
    flex: 1,
    justifyContent: 'center',
    paddingVertical: spacing.xl,
    gap: spacing.l,
  },
  stepBadge: {
    alignSelf: 'center',
  },
  heading: {
    alignItems: 'center',
    gap: spacing.s,
  },
  input: {
    marginTop: spacing.s,
  },
});
