// RCC-0.5 / Wave 1 — InstructorButton backend-driven
// Avatar e dados vêm de v_instrutores_app via useInstructors().
// Nenhum hardcode de nome, imagem ou descrição.
//
// Comportamento:
//   - instrutor selecionado → toque abre chat direto
//   - sem instrutor → toque abre seletor 3D
//   - troca de instrutor: disponível apenas no Perfil do aluno

import React from 'react';
import { useRouter } from 'expo-router';
import { useAuth } from '../../context/AuthContext';
import { useInstructors } from '../../hooks/useInstructors';
import { FORCE_GLOW, DEFAULT_GLOW } from '../../constants/instructors';
import { InstructorAvatar } from './InstructorAvatar';

// Avatares locais (bundled): fallback quando avatar_url remoto for null/falhar.
const LOCAL_AVATARS: Record<string, any> = {
  ramos: require('../../../assets/instructors/avatars/ramos-avatar-circle.png'),
  rocha: require('../../../assets/instructors/avatars/rocha-avatar-circle.png'),
  sara:  require('../../../assets/instructors/avatars/sara-avatar-circle.png'),
};

export default function InstructorButton() {
  const router = useRouter();
  const { profile } = useAuth();
  const { instructors } = useInstructors();

  const forca = profile?.forca ?? 'marinha';
  const glowColor = FORCE_GLOW[forca] ?? DEFAULT_GLOW;
  const hasInstructor = !!profile?.instructor_profile_id;

  const currentInstructor =
    instructors.find((i) => i.codigo === profile?.instructor_profile_id) ?? null;

  const resolvedSlug = currentInstructor?.slug ?? null;
  // Local asset é obrigatório — não depende de avatar_url remoto.
  // avatar_url remoto pode ser null, inválido ou lento; local é sempre bundled.
  const localSource = resolvedSlug ? (LOCAL_AVATARS[resolvedSlug] ?? null) : null;
  const remoteSource = currentInstructor?.avatar_url
    ? { uri: currentInstructor.avatar_url }
    : null;
  const avatarSource = localSource ?? remoteSource;

  console.log('[INSTRUCTOR_BUTTON_AVATAR]', {
    codigo: profile?.instructor_profile_id ?? null,
    resolvedSlug,
    hasLocalAvatar: !!localSource,
    hasRemoteAvatar: !!remoteSource,
    sourceType: localSource ? 'local' : remoteSource ? 'remote' : 'none',
  });

  function handleAvatarPress() {
    if (!hasInstructor) {
      router.push('/(stack)/instructor/select' as any);
      return;
    }
    router.push('/(tabs)/chat' as any);
  }

  return (
    <InstructorAvatar
      avatarSource={avatarSource}
      glowColor={glowColor}
      onPress={handleAvatarPress}
    />
  );
}
