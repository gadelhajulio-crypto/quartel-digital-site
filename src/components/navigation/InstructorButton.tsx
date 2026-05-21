// RCC-0.5 / Wave 2b — InstructorButton backend-driven
// Avatar e dados vêm de v_instrutores_app via useInstructors().
// unread_count vem de v_chat_conversas_recruta via useChatUnread() — banco é verdade.
// Nenhum hardcode de nome, imagem, descrição ou contagem de unread.
//
// Comportamento:
//   - instrutor selecionado → toque abre chat direto
//   - sem instrutor → toque abre seletor 3D
//   - troca de instrutor: disponível apenas no Perfil do aluno

import React from 'react';
import { useRouter } from 'expo-router';
import { useAuth } from '../../context/AuthContext';
import { useInstructors } from '../../hooks/useInstructors';
import { useChatUnread } from '../../hooks/useChatUnread';
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

  // instructorCodigo = objetivo/estrategico/didatico — chave do chat institucional
  const instructorCodigo = profile?.instructor_profile_id ?? null;
  const { unreadCount } = useChatUnread(instructorCodigo);

  const currentInstructor =
    instructors.find((i) => i.codigo === instructorCodigo) ?? null;

  const resolvedSlug = currentInstructor?.slug ?? null;
  // Local asset é obrigatório — não depende de avatar_url remoto.
  const localSource = resolvedSlug ? (LOCAL_AVATARS[resolvedSlug] ?? null) : null;
  const remoteSource = currentInstructor?.avatar_url
    ? { uri: currentInstructor.avatar_url }
    : null;
  const avatarSource = localSource ?? remoteSource;

  function handleAvatarPress() {
    if (!hasInstructor) {
      router.push('/(stack)/instructor/select' as any);
      return;
    }
    router.push('/(stack)/conversations' as any);
  }

  return (
    <InstructorAvatar
      avatarSource={avatarSource}
      glowColor={glowColor}
      onPress={handleAvatarPress}
      unreadCount={unreadCount}
    />
  );
}
