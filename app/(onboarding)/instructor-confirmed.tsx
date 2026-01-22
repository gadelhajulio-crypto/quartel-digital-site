import { View, ActivityIndicator, StyleSheet } from 'react-native';
import { useEffect } from 'react';
import { useRouter } from 'expo-router';

/**
 * TELA DE FALLBACK / COMPATIBILIDADE
 *
 * Esta tela NÃO faz mais parte do fluxo principal.
 * Ela existe apenas para:
 * - evitar crashes se algum fluxo antigo apontar para cá
 * - redirecionar imediatamente para o Painel
 *
 * Não contém lógica de instrutor
 * Não contém fetch
 * Não contém UI emocional
 */

export default function InstructorConfirmedScreen() {
  const router = useRouter();

  useEffect(() => {
    // Redirecionamento imediato para o painel
    const timeout = setTimeout(() => {
      router.replace('/(app)/painel');
    }, 300); // delay mínimo apenas para evitar glitch de navegação

    return () => clearTimeout(timeout);
  }, []);

  return (
    <View style={styles.container}>
      <ActivityIndicator size="large" color="#38BDF8" />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#0F172A',
    justifyContent: 'center',
    alignItems: 'center',
  },
});
