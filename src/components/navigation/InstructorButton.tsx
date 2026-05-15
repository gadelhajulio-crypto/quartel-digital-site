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

export default function InstructorButton() {
  const router = useRouter();
  const { profile } = useAuth();
  const { instructors } = useInstructors();

  const forca = profile?.forca ?? 'marinha';
  const glowColor = FORCE_GLOW[forca] ?? DEFAULT_GLOW;
  const hasInstructor = !!profile?.instructor_profile_id;

  const currentInstructor =
    instructors.find((i) => i.codigo === profile?.instructor_profile_id) ?? null;

  const avatarSource = currentInstructor?.avatar_url
    ? { uri: currentInstructor.avatar_url }
    : null;

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
