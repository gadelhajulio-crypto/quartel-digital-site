import { View, Text, StyleSheet, Switch, TouchableOpacity, ScrollView, Linking } from 'react-native';
import { useState } from 'react';
import { useRouter } from 'expo-router';
import { ObsidianScreen } from '../../src/design/layout/ObsidianScreen';
import { InstitutionalHeader } from '../../src/design/components/InstitutionalHeader';
import { InstitutionalSection } from '../../src/design/components/InstitutionalSection';
import { InstitutionalCard } from '../../src/design/components/InstitutionalCard';
import { obsidiana } from '../../src/design/themes/obsidiana';
import { typographyPresets } from '../../src/design/tokens/typography';
import { spacing } from '../../src/design/tokens/spacing';

export default function ConfiguracoesScreen() {
  const router = useRouter();
  const [soundEnabled, setSoundEnabled] = useState(true);
  const [vibrationEnabled, setVibrationEnabled] = useState(true);

  return (
    <ObsidianScreen>
      <InstitutionalHeader title="Configurações" theme={obsidiana} />

      <ScrollView
        contentContainerStyle={styles.scroll}
        showsVerticalScrollIndicator={false}
      >
        {/* PREFERÊNCIAS */}
        <InstitutionalSection title="Preferências" theme={obsidiana}>
          <InstitutionalCard theme={obsidiana}>
            <View style={[styles.row, { borderBottomColor: obsidiana.colors.border }]}>
              <Text style={[typographyPresets.cardTitle, { color: obsidiana.colors.text }]}>
                Som do app
              </Text>
              <Switch
                value={soundEnabled}
                onValueChange={setSoundEnabled}
                trackColor={{
                  true: obsidiana.colors.accent,
                  false: obsidiana.colors.muted,
                }}
                thumbColor={obsidiana.colors.text}
              />
            </View>
            <View style={styles.row}>
              <Text style={[typographyPresets.cardTitle, { color: obsidiana.colors.text }]}>
                Vibração
              </Text>
              <Switch
                value={vibrationEnabled}
                onValueChange={setVibrationEnabled}
                trackColor={{
                  true: obsidiana.colors.accent,
                  false: obsidiana.colors.muted,
                }}
                thumbColor={obsidiana.colors.text}
              />
            </View>
          </InstitutionalCard>
        </InstitutionalSection>

        {/* SEGURANÇA */}
        <InstitutionalSection title="Segurança" theme={obsidiana}>
          <InstitutionalCard theme={obsidiana}>
            <LinkItem
              label="Sessões ativas"
              onPress={() => router.push('/(stack)/sessions')}
            />
          </InstitutionalCard>
        </InstitutionalSection>

        {/* INSTITUCIONAL */}
        <InstitutionalSection title="Institucional" theme={obsidiana}>
          <InstitutionalCard theme={obsidiana}>
            <LinkItem
              label="Termos de uso"
              onPress={() => Linking.openURL('https://recrutapadrao.com.br/temosdeuso/')}
              divider
            />
            <LinkItem
              label="Privacidade e uso de dados"
              onPress={() =>
                Linking.openURL(
                  'https://recrutapadrao.com.br/politica-de-privacidade-quartel-digital/'
                )
              }
              divider
            />
            <LinkItem
              label="Sobre o Quartel Digital"
              onPress={() =>
                Linking.openURL('https://recrutapadrao.com.br/quarteldigital/')
              }
            />
          </InstitutionalCard>
        </InstitutionalSection>

        <View style={{ height: 120 }} />
      </ScrollView>
    </ObsidianScreen>
  );
}

function LinkItem({
  label,
  onPress,
  divider = false,
}: {
  label: string;
  onPress: () => void;
  divider?: boolean;
}) {
  return (
    <>
      <TouchableOpacity
        style={styles.linkItem}
        onPress={onPress}
        activeOpacity={0.7}
      >
        <Text style={[typographyPresets.cardTitle, { color: obsidiana.colors.text }]}>
          {label}
        </Text>
        <Text style={{ color: obsidiana.colors.muted, fontSize: 18 }}>›</Text>
      </TouchableOpacity>
      {divider && (
        <View style={[styles.divider, { backgroundColor: obsidiana.colors.border }]} />
      )}
    </>
  );
}

const styles = StyleSheet.create({
  scroll: {
    padding: spacing.m,
    paddingBottom: 120,
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: spacing.m,
    borderBottomWidth: 1,
    borderBottomColor: 'transparent',
  },
  linkItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: spacing.m,
  },
  divider: {
    height: 1,
  },
});
