// RCC-0.5 / Wave 1 — Onboarding: seleção de instrutor
// Fonte: v_instrutores_app (backend-driven, sem hardcode).
// Confirma via rpc_update_instructor_profile(slug) → retriggerGate.

import { useState, useEffect } from 'react';
import { View, Text, Image, TouchableOpacity, ActivityIndicator, StyleSheet } from 'react-native';
import { useAuth } from '../../src/context/AuthContext';
import { useBootstrapGate } from '../../src/context/BootstrapGateContext';
import { supabase } from '../../src/lib/supabase';
import { loadInstructors, type InstructorApp } from '../../src/services/chatService';
import { clearInstructorsCache } from '../../src/hooks/useInstructors';
import { ObsidianScreen } from '../../src/design/layout/ObsidianScreen';
import { InstitutionalCard } from '../../src/design/components/InstitutionalCard';
import { InstitutionalButton } from '../../src/design/components/InstitutionalButton';
import { InstitutionalBadge } from '../../src/design/components/InstitutionalBadge';
import { obsidiana } from '../../src/design/themes/obsidiana';
import { typographyPresets } from '../../src/design/tokens/typography';
import { spacing } from '../../src/design/tokens/spacing';
import { radius } from '../../src/design/tokens/radius';

export default function OnboardingInstrutor() {
  const { refetchProfile } = useAuth();
  const { retriggerGate } = useBootstrapGate();

  const [instructors, setInstructors] = useState<InstructorApp[]>([]);
  const [loadingInstructors, setLoadingInstructors] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);

  const [selected, setSelected] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  useEffect(() => {
    console.log('[INSTRUCTOR_UX_W1] load_start');
    loadInstructors()
      .then((data) => {
        console.log('[INSTRUCTOR_UX_W1] load_success', { count: data.length });
        setInstructors(data);
      })
      .catch((err) => {
        console.warn('[INSTRUCTOR_UX_W1] load_error', { msg: err?.message });
        setLoadError('Não foi possível carregar os instrutores. Verifique sua conexão.');
      })
      .finally(() => setLoadingInstructors(false));
  }, []);

  async function confirmar() {
    if (!selected || saving) return;
    setSaving(true);
    setSaveError(null);

    const rpcPayload = { p_instructor_profile_id: selected };
    const selectedInstructor = instructors.find((i) => i.slug === selected) ?? null;

    console.log('[INSTRUCTOR_RPC_CALL]', {
      selectedInstructor,
      p_instructor_profile_id: selected,
      slug: selectedInstructor?.slug ?? null,
      codigo: selectedInstructor?.codigo ?? null,
    });

    try {
      const { data, error } = await supabase.rpc('rpc_update_instructor_profile', rpcPayload);

      if (error) {
        console.warn('[INSTRUCTOR_SELECT_RPC] error', {
          message: error.message,
          code: error.code,
          details: error.details,
          hint: error.hint,
        });
        setSaveError(error.message || 'Não foi possível registrar. Tente novamente.');
        setSaving(false);
        return;
      }

      console.log('[INSTRUCTOR_SELECT_RPC] success', { slug: selected, data });

      clearInstructorsCache();
      await refetchProfile();

      console.log('[INSTRUCTOR_UX_W1] profile_refetch_done');
      retriggerGate();
    } catch (err: any) {
      const msg = err?.message ?? String(err);
      console.warn('[INSTRUCTOR_SELECT_RPC] error', { message: msg });
      setSaveError(msg || 'Não foi possível registrar. Tente novamente.');
      setSaving(false);
    }
  }

  return (
    <ObsidianScreen scrollable contentStyle={styles.content}>
      {/* Cabeçalho */}
      <View style={styles.heading}>
        <InstitutionalBadge
          theme={obsidiana}
          label="Instrutor Virtual"
          variant="accent"
          style={styles.badge}
        />
        <Text
          style={[
            typographyPresets.sectionTitle,
            { color: obsidiana.colors.accent, textAlign: 'center' },
          ]}
        >
          Escolha seu instrutor.
        </Text>
        <Text
          style={[
            typographyPresets.body,
            { color: obsidiana.colors.textSecondary, textAlign: 'center' },
          ]}
        >
          Cada instrutor tem uma abordagem diferente.{'\n'}
          Você pode alterar depois.
        </Text>
      </View>

      {/* Loading */}
      {loadingInstructors && (
        <View style={styles.loadingCenter}>
          <ActivityIndicator color={obsidiana.colors.accent} />
        </View>
      )}

      {/* Erro no carregamento */}
      {loadError && !loadingInstructors && (
        <InstitutionalBadge
          theme={obsidiana}
          label={loadError}
          variant="error"
          style={styles.errorBadge}
        />
      )}

      {/* Cards de seleção */}
      {!loadingInstructors &&
        instructors.map((instructor) => {
          const isSelected = selected === instructor.codigo;
          const imageSource = isSelected
            ? instructor.card_selected_url
            : instructor.card_idle_url;

          return (
            <TouchableOpacity
              key={instructor.instrutor_id}
              activeOpacity={0.88}
              onPress={() => {
                setSelected(instructor.codigo);
                console.log('[INSTRUCTOR_UX_W1] selected', { codigo: instructor.codigo });
              }}
              style={styles.cardWrapper}
            >
              <InstitutionalCard
                theme={obsidiana}
                style={[
                  styles.card,
                  isSelected && { borderColor: obsidiana.colors.accent, borderWidth: 2 },
                ]}
              >
                {/* Imagem de apresentação */}
                <View style={styles.imageContainer}>
                  {imageSource ? (
                    <Image
                      source={{ uri: imageSource }}
                      style={styles.image}
                      resizeMode="cover"
                    />
                  ) : (
                    <View
                      style={[styles.image, { backgroundColor: obsidiana.colors.surface }]}
                    />
                  )}

                  {/* Badge de posto flutuante */}
                  <View style={styles.rankBadge}>
                    <InstitutionalBadge
                      theme={obsidiana}
                      label={instructor.titulo}
                      variant="muted"
                    />
                  </View>

                  {/* Indicador de seleção */}
                  {isSelected && (
                    <View
                      style={[
                        styles.selectedIndicator,
                        { backgroundColor: obsidiana.colors.accent },
                      ]}
                    >
                      <Text style={styles.checkmark}>✓</Text>
                    </View>
                  )}
                </View>

                {/* Conteúdo textual */}
                <View style={styles.cardBody}>
                  <Text
                    style={[
                      typographyPresets.cardTitle,
                      {
                        color: isSelected
                          ? obsidiana.colors.accent
                          : obsidiana.colors.text,
                      },
                    ]}
                  >
                    {instructor.nome}
                  </Text>

                  {instructor.descricao ? (
                    <>
                      <View
                        style={[
                          styles.divider,
                          { backgroundColor: obsidiana.colors.border },
                        ]}
                      />
                      <Text
                        style={[
                          typographyPresets.bodySmall,
                          { color: obsidiana.colors.textSecondary },
                        ]}
                      >
                        {instructor.descricao}
                      </Text>
                    </>
                  ) : null}
                </View>
              </InstitutionalCard>
            </TouchableOpacity>
          );
        })}

      {/* Erro ao salvar */}
      {saveError && (
        <InstitutionalBadge
          theme={obsidiana}
          label={saveError}
          variant="error"
          style={styles.errorBadge}
        />
      )}

      {/* Botão confirmar */}
      <InstitutionalButton
        theme={obsidiana}
        label="Confirmar instrutor"
        onPress={confirmar}
        loading={saving}
        disabled={!selected || saving}
        size="l"
        style={styles.confirmBtn}
      />

      {/* Aviso institucional */}
      <Text
        style={[
          typographyPresets.label,
          { color: obsidiana.colors.muted, textAlign: 'center', marginBottom: spacing.xl },
        ]}
      >
        O instrutor não acessa dados pessoais externos.{'\n'}
        Opera dentro do Quartel Digital.
      </Text>
    </ObsidianScreen>
  );
}

const styles = StyleSheet.create({
  content: {
    paddingTop: spacing.xl,
  },
  heading: {
    alignItems: 'center',
    gap: spacing.s,
    marginBottom: spacing.xl,
  },
  badge: {
    marginBottom: spacing.xs,
  },
  loadingCenter: {
    paddingVertical: spacing.xl,
    alignItems: 'center',
  },
  cardWrapper: {
    marginBottom: spacing.m,
  },
  card: {
    padding: 0,
    overflow: 'hidden',
  },
  imageContainer: {
    height: 200,
    position: 'relative',
  },
  image: {
    width: '100%',
    height: '100%',
  },
  rankBadge: {
    position: 'absolute',
    top: spacing.s,
    left: spacing.s,
  },
  selectedIndicator: {
    position: 'absolute',
    top: spacing.s,
    right: spacing.s,
    width: 28,
    height: 28,
    borderRadius: radius.full,
    alignItems: 'center',
    justifyContent: 'center',
  },
  checkmark: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '700',
  },
  cardBody: {
    padding: spacing.m,
    gap: spacing.xs,
  },
  divider: {
    height: 1,
    marginVertical: spacing.s,
  },
  errorBadge: {
    alignSelf: 'stretch',
    marginBottom: spacing.m,
  },
  confirmBtn: {
    marginBottom: spacing.m,
  },
});
