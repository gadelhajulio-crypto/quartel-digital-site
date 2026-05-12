import { View, Text, StyleSheet, Image, ScrollView, Dimensions, TouchableOpacity } from 'react-native';
import { useLocalSearchParams, useRouter, Stack } from 'expo-router';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useForceTheme } from '../../../src/context/ForceThemeContext';
import { Ionicons } from '@expo/vector-icons';


const { width, height } = Dimensions.get('window');

import { instructorAssets } from '@/assets/instructors';

// Asset mapping for CONFIRMATION images (different from selection if validated, 
// strictly using what was in _layout.tsx preload list)
const CONFIRM_ASSETS: Record<string, any> = {
  'objetivo': instructorAssets.marinha.objetivo.confirmacao,
  'estrategico': instructorAssets.marinha.estrategico.confirmacao,
  'didatico': instructorAssets.marinha.didatico.confirmacao,
};

const INSTRUCTOR_DATA: Record<string, any> = {
  'objetivo': {
    name: 'Instrutor Objetivo',
    color: '#1F6FEB',
    welcome: 'Excelente escolha, Recruta. Aqui não há espaço para desculpas. Vamos ao trabalho.'
  },
  'estrategico': {
    name: 'Instrutor Estratégico',
    color: '#238636',
    welcome: 'Bem-vindo. Entenda as regras do jogo e você vencerá. Vamos analisar seu próximo passo.'
  },
  'didatico': {
    name: 'Instrutora Didática',
    color: '#A371F7',
    welcome: 'Olá! Fico feliz em guiar você. Vamos aprender tudo com calma e garantir sua aprovação.'
  }
};

export default function InstructorConfirmScreen() {
  const { instructorId } = useLocalSearchParams<{ instructorId: string }>();
  const router = useRouter();
  const { theme } = useForceTheme();

  const id = instructorId || 'objetivo'; // Fallback
  const data = INSTRUCTOR_DATA[id];
  const imageSource = CONFIRM_ASSETS[id];



  const handleSkip = () => {
    router.replace('/(tabs)');
  };

  return (
    <View style={[styles.container, { backgroundColor: '#000' }]}>
      <Stack.Screen options={{ headerShown: false }} />
      {/* Full Screen Image Background effect or just large image */}
      <View style={styles.imageContainer}>
        <Image
          source={imageSource}
          style={styles.image}
          resizeMode="cover" // 1:1 centralization usually implies full focus
        />
        {/* Gradient overlay could be adding here if needed, but keeping it simple as requested */}
      </View>

      <View style={styles.contentOverlay}>
        <View
          style={[styles.card, { backgroundColor: theme.card || '#1A1A1A' }]}
        >
          <View style={[styles.indicator, { backgroundColor: data.color }]} />

          <Text style={[styles.title, { color: theme.textPrimary }]}>
            CONFIRMADO
          </Text>

          <Text style={[styles.instructorName, { color: data.color }]}>
            {data.name}
          </Text>

          <ScrollView style={{ marginTop: 16, marginBottom: 16 }} contentContainerStyle={{ flexGrow: 1 }}>
            <Text style={[styles.message, { color: theme.textSecondary }]}>
              "{data.welcome}"
            </Text>
          </ScrollView>

          <TouchableOpacity
            style={[styles.button, { backgroundColor: data.color }]}
            onPress={handleSkip}
          >
            <Text style={styles.buttonText}>INICIAR TREINAMENTO</Text>
            <Ionicons name="arrow-forward" size={20} color="#FFF" />
          </TouchableOpacity>

        </View>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  imageContainer: {
    width: width,
    height: height * 0.65, // Use top 65% for image
    justifyContent: 'flex-end',
  },
  image: {
    width: '100%',
    height: '100%',
  },
  contentOverlay: {
    flex: 1,
    backgroundColor: '#000', // Fill rest
    justifyContent: 'flex-end',
  },
  card: {
    borderTopLeftRadius: 30,
    borderTopRightRadius: 30,
    padding: 30,
    paddingBottom: 50, // Safe area
    minHeight: height * 0.4,
    alignItems: 'center',
  },
  indicator: {
    width: 40,
    height: 4,
    borderRadius: 2,
    marginBottom: 20,
  },
  title: {
    fontSize: 14,
    letterSpacing: 2,
    fontWeight: 'bold',
    marginBottom: 8,
    opacity: 0.7,
  },
  instructorName: {
    fontSize: 24,
    fontWeight: 'bold',
    marginBottom: 16,
    textAlign: 'center',
  },
  message: {
    fontSize: 16,
    lineHeight: 24,
    textAlign: 'center',
    fontStyle: 'italic',
    marginBottom: 20,
  },
  button: {
    flexDirection: 'row',
    width: '100%',
    height: 56,
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
    gap: 12,
    marginTop: 20,
  },
  buttonText: {
    color: '#FFF',
    fontSize: 16,
    fontWeight: 'bold',
    letterSpacing: 1,
  },
});
