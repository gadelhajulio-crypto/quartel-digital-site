// RCC-0.5 / Wave 1 — Seleção/Troca de Instrutor Institucional
// Fonte: v_instrutores_app (backend-driven, sem hardcode).
// Confirmação via rpc_update_instructor_profile.
// Acessível pós-onboarding para troca de instrutor.

import React, { useState } from 'react';
import {
  View,
  Text,
  ScrollView,
  TouchableOpacity,
  Image,
  ActivityIndicator,
  Platform,
  StyleSheet,
} from 'react-native';
import { useRouter } from 'expo-router';
import { supabase } from '../../../src/lib/supabase';
import { useAuth } from '../../../src/context/AuthContext';
import { useInstructors, clearInstructorsCache } from '../../../src/hooks/useInstructors';
import { type InstructorApp } from '../../../src/services/chatService';
import { InstitutionalHeader } from '../../../src/design/components/InstitutionalHeader';
import { InstitutionalButton } from '../../../src/design/components/InstitutionalButton';
import { InstitutionalBadge } from '../../../src/design/components/InstitutionalBadge';
import { tatico } from '../../../src/design/themes/tatico';
import { typographyPresets } from '../../../src/design/tokens/typography';
import { spacing } from '../../../src/design/tokens/spacing';
import { radius } from '../../../src/design/tokens/radius';

type UxState = 'idle' | 'saving' | 'success' | 'error';

export default function SelectInstructorScreen() {
  const router = useRouter();
  const { profile, refetchProfile } = useAuth();
  const { instructors, loading: loadingInstructors, error: loadError } = useInstructors();

  const [selected, setSelected] = useState<string | null>(
    profile?.instructor_profile_id ?? null,
  );
  const [uxState, setUxState] = useState<UxState>('idle');
  const [errorMsg, setErrorMsg] = useState('');

  console.log('[INSTRUCTOR_UX_W1] load_start');

  function handleBack() {
    if (router.canGoBack()) router.back();
    else router.replace('/(tabs)/chat');
  }

  async function handleConfirm() {
    if (!selected || uxState === 'saving') return;
    setErrorMsg('');
    setUxState('saving');

    console.log('[INSTRUCTOR_UX_W1] update_start', { selected });

    try {
      const { error: rpcError } = await supabase.rpc('rpc_update_instructor_profile', {
        p_instructor_profile_id: selected,
      });

      if (rpcError) {
        console.warn('[INSTRUCTOR_UX_W1] update_error', { msg: rpcError.message });
        setErrorMsg('Não foi possível salvar a seleção. Tente novamente.');
        setUxState('error');
        return;
      }

      console.log('[INSTRUCTOR_UX_W1] update_success');

      clearInstructorsCache();
      await refetchProfile();

      console.log('[INSTRUCTOR_UX_W1] profile_refetch_done');
      setUxState('success');

      router.replace('/(tabs)/chat');
    } catch (err: any) {
      console.warn('[INSTRUCTOR_UX_W1] update_error', { msg: err?.message ?? err });
      setErrorMsg('Erro inesperado. Tente novamente.');
      setUxState('error');
    }
  }

  function handleSelect(instructor: InstructorApp) {
    if (uxState === 'saving') return;
    setSelected(instructor.codigo);
    console.log('[INSTRUCTOR_UX_W1] selected', { codigo: instructor.codigo });
  }

  const isSaving = uxState === 'saving';

  return (
    <View style={[styles.root, { backgroundColor: tatico.colors.background }]}>
      <InstitutionalHeader
        theme={tatico as any}
        title="Selecionar instrutor"
        subtitle="Canal do Instrutor Virtual"
        onBack={handleBack}
        style={styles.header}
      />

      <ScrollView
        style={styles.scroll}
        contentContainerStyle={styles.content}
        showsVerticalScrollIndicator={false}
      >
        {/* Título */}
        <View style={styles.intro}>
          <InstitutionalBadge
            theme={tatico as any}
            label="Instrutor institucional"
            variant="accent"
          />
          <Text
            style={[
              typographyPresets.sectionTitle,
              { color: tatico.colors.text, marginTop: 12 },
            ]}
          >
            Escolha o instrutor que acompanhará sua jornada institucional.
          </Text>
        </View>

        {/* Loading */}
        {loadingInstructors && (
          <View style={styles.loadingCenter}>
            <ActivityIndicator color={tatico.colors.accent} />
          </View>
        )}

        {/* Erro real de rede ou servidor — não exibir para lista vazia */}
        {loadError && !loadingInstructors && instructors.length === 0 && (
          <InstitutionalBadge
            theme={tatico as any}
            label="Não foi possível carregar os instrutores. Verifique sua conexão."
            variant="error"
            style={styles.errorBadge}
          />
        )}

        {/* Cards de instrutores */}
        {!loadingInstructors &&
          instructors.map((instructor) => {
            const isSelected = selected === instructor.codigo;
            const imageSource = isSelected
              ? instructor.card_selected_url
              : instructor.card_idle_url;

            return (
              <TouchableOpacity
                key={instructor.instrutor_id}
                style={[
                  styles.card,
                  {
                    backgroundColor: tatico.colors.card,
                    borderColor: isSelected
                      ? tatico.colors.accent
                      : tatico.colors.border,
                    borderWidth: isSelected ? 2 : 1,
                  },
                ]}
                onPress={() => handleSelect(instructor)}
                activeOpacity={0.78}
                disabled={isSaving}
              >
                {/* Imagem do card */}
                {imageSource ? (
                  <Image
                    source={{ uri: imageSource }}
                    style={styles.cardImage}
                    resizeMode="cover"
                  />
                ) : (
                  <View
                    style={[
                      styles.cardImage,
                      { backgroundColor: tatico.colors.surface },
                    ]}
                  />
                )}

                <View style={styles.cardBody}>
                  <View style={styles.cardTop}>
                    <Text
                      style={[
                        typographyPresets.cardTitle,
                        { color: tatico.colors.text, flex: 1 },
                      ]}
                    >
                      {instructor.nome}
                    </Text>
                    {isSelected && (
                      <InstitutionalBadge
                        theme={tatico as any}
                        label="Selecionado"
                        variant="success"
                      />
                    )}
                  </View>

                  <Text
                    style={[
                      typographyPresets.label,
                      { color: tatico.colors.accent, marginTop: 2, marginBottom: 6 },
                    ]}
                  >
                    {instructor.titulo}
                  </Text>

                  {instructor.descricao ? (
                    <Text
                      style={[
                        typographyPresets.bodySmall,
                        { color: tatico.colors.textSecondary },
                      ]}
                    >
                      {instructor.descricao}
                    </Text>
                  ) : null}
                </View>
              </TouchableOpacity>
            );
          })}

        {/* Erro ao salvar */}
        {uxState === 'error' && errorMsg !== '' && (
          <InstitutionalBadge
            theme={tatico as any}
            label={errorMsg}
            variant="error"
            style={styles.errorBadge}
          />
        )}

        {/* Confirmação */}
        <InstitutionalButton
          theme={tatico as any}
          label={isSaving ? 'Salvando...' : 'CONFIRMAR INSTRUTOR'}
          onPress={handleConfirm}
          disabled={!selected || isSaving || loadingInstructors}
          loading={isSaving}
          size="l"
          style={styles.confirmBtn}
        />

        <View style={{ height: 40 }} />
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  header: {
    paddingTop: Platform.OS === 'ios' ? 52 : 16,
  },
  scroll: { flex: 1 },
  content: {
    padding: spacing.m,
    gap: spacing.m,
  },
  intro: {
    marginBottom: spacing.s,
  },
  loadingCenter: {
    paddingVertical: spacing.xl,
    alignItems: 'center',
  },
  card: {
    borderRadius: radius.m,
    overflow: 'hidden',
  },
  cardImage: {
    width: '100%',
    height: 180,
  },
  cardBody: {
    padding: spacing.m,
  },
  cardTop: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: spacing.s,
  },
  errorBadge: {
    alignSelf: 'stretch',
  },
  confirmBtn: {
    marginTop: spacing.s,
    alignSelf: 'stretch',
  },
});
