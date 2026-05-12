// RCC-0.5 / Wave 1 — InstructorButton backend-driven
// Avatar e dados vêm de v_instrutores_app via useInstructors().
// Nenhum hardcode de nome, imagem ou descrição.

import React, { useState } from 'react';
import { useRouter } from 'expo-router';
import { useAuth } from '../../context/AuthContext';
import { useInstructors } from '../../hooks/useInstructors';
import { FORCE_GLOW, DEFAULT_GLOW } from '../../constants/instructors';
import { InstructorAvatar } from './InstructorAvatar';
import { InstructorSheet } from './InstructorSheet';

export default function InstructorButton() {
  const router = useRouter();
  const { profile } = useAuth();
  const { instructors } = useInstructors();
  const [sheetOpen, setSheetOpen] = useState(false);

  const forca = profile?.forca ?? 'marinha';
  const glowColor = FORCE_GLOW[forca] ?? DEFAULT_GLOW;
  const hasInstructor = !!profile?.instructor_profile_id;

  // Encontrar instrutor atual pelo codigo (objetivo / estrategico / didatico)
  const currentInstructor =
    instructors.find((i) => i.codigo === profile?.instructor_profile_id) ?? null;

  // Source do avatar: URI do backend ou placeholder local
  const avatarSource = currentInstructor?.avatar_url
    ? { uri: currentInstructor.avatar_url }
    : require('../../../assets/instructors/avatars/ramos-avatar-circle.png');

  function handleAvatarPress() {
    if (!hasInstructor) {
      router.push('/(stack)/instructor/select' as any);
      return;
    }
    setSheetOpen(true);
  }

  function handleChatPress() {
    setSheetOpen(false);
    setTimeout(() => router.push('/(tabs)/chat'), 240);
  }

  function handleChangePress() {
    setSheetOpen(false);
    setTimeout(() => router.push('/(stack)/instructor/select' as any), 240);
  }

  return (
    <>
      <InstructorAvatar
        avatarSource={avatarSource}
        glowColor={glowColor}
        onPress={handleAvatarPress}
        active={sheetOpen}
      />

      {currentInstructor && (
        <InstructorSheet
          visible={sheetOpen}
          instructor={currentInstructor}
          glowColor={glowColor}
          onDismiss={() => setSheetOpen(false)}
          onChatPress={handleChatPress}
          onChangePress={handleChangePress}
        />
      )}
    </>
  );
}
