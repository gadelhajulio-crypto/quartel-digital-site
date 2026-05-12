import React, { useState, useRef, useCallback } from 'react';
import { View, Text, StyleSheet, Dimensions, TouchableOpacity, FlatList, Image, Platform } from 'react-native';
import { useRouter, Stack } from 'expo-router';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useForceTheme } from '../../../src/context/ForceThemeContext';
import { useAuth } from '../../../src/context/AuthContext';
import { supabase } from '../../../src/lib/supabase';
import { Ionicons } from '@expo/vector-icons';
import Animated, {
  useSharedValue,
  useAnimatedStyle,
  withSpring,
  useAnimatedScrollHandler,
  interpolate,
  Extrapolate,
  SharedValue
} from 'react-native-reanimated';


const { width, height } = Dimensions.get('window');
const ITEM_WIDTH = width; // Full width cards

import { instructorAssets } from '@/assets/instructors';

// Assets mapping based on validated paths
const INSTRUCTORS = [
  {
    id: 'objetivo',
    name: 'Instrutor Objetivo',
    badge: 'Foco no Resultado',
    description: 'Direto ao ponto. Sem rodeios. Treinamento intensivo focado em regulamentos e execução perfeita.',
    image: instructorAssets.marinha.objetivo.selecao,
    color: '#1F6FEB', // Blue
    traits: ['Disciplina', 'Rigor', 'Clareza']
  },
  {
    id: 'estrategico',
    name: 'Instrutor Estratégico',
    badge: 'Visão de Longo Prazo',
    description: 'Analisa o porquê das ordens. Focado em liderança, hierarquia e construção de carreira.',
    image: instructorAssets.marinha.estrategico.selecao,
    color: '#238636', // Green
    traits: ['Liderança', 'Análise', 'Carreira']
  },
  {
    id: 'didatico',
    name: 'Instrutora Didática',
    badge: 'Aprendizado Acelerado',
    description: 'Ensino passo a passo. Focada em garantir que você entenda cada detalhe antes de avançar.',
    image: instructorAssets.marinha.didatico.selecao,
    color: '#A371F7', // Purple
    traits: ['Paciência', 'Detalhes', 'Método']
  }
];

// Extracted Component to fix Invalid Hook Call
const InstructorCard = ({ item, index, scrollX }: { item: typeof INSTRUCTORS[0], index: number, scrollX: SharedValue<number> }) => {
  const { theme } = useForceTheme();

  const animatedStyle = useAnimatedStyle(() => {
    const inputRange = [
      (index - 1) * width,
      index * width,
      (index + 1) * width,
    ];

    const scale = interpolate(
      scrollX.value,
      inputRange,
      [0.9, 1, 0.9],
      Extrapolate.CLAMP
    );

    const opacity = interpolate(
      scrollX.value,
      inputRange,
      [0.6, 1, 0.6],
      Extrapolate.CLAMP
    );

    return {
      transform: [{ scale }],
      opacity,
    };
  });

  return (
    <View style={{ width, alignItems: 'center', justifyContent: 'center' }}>
      <Animated.View style={[styles.cardContainer, { backgroundColor: theme.card }, animatedStyle]}>
        <View style={styles.imageContainer}>
          <Image
            source={item.image}
            style={styles.instructorImage}
            resizeMode="cover"
          />
          <View style={[styles.badge, { backgroundColor: item.color }]}>
            <Text style={styles.badgeText}>{item.badge}</Text>
          </View>
        </View>

        <View style={styles.infoContainer}>
          <Text style={[styles.name, { color: theme.textPrimary }]}>{item.name}</Text>
          <View style={styles.traitsContainer}>
            {item.traits.map(trait => (
              <View key={trait} style={[styles.traitTag, { borderColor: theme.textSecondary }]}>
                <Text style={[styles.traitText, { color: theme.textSecondary }]}>{trait}</Text>
              </View>
            ))}
          </View>
          <Text style={[styles.description, { color: theme.textSecondary }]}>
            {item.description}
          </Text>
        </View>
      </Animated.View>
    </View>
  );
};

export default function InstructorSelectScreen() {
  const router = useRouter();
  const { session, refetchProfile } = useAuth();
  const { theme } = useForceTheme();
  const [currentIndex, setCurrentIndex] = useState(0);
  const scrollX = useSharedValue(0);
  const flatListRef = useRef<FlatList>(null);

  const handleScroll = useAnimatedScrollHandler({
    onScroll: (event) => {
      scrollX.value = event.contentOffset.x;
    },
  });

  const handleConfirm = async () => {
    const selectedInstructor = INSTRUCTORS[currentIndex];

    // 2. Optimistic Navigation (Immediate)
    router.push({
      pathname: '/(onboarding)/instructor-confirm',
      params: { instructorId: selectedInstructor.id }
    });

    // 3. Background Update
    if (session) {
      try {
        const { error } = await supabase.rpc('rpc_set_instructor_profile', {
          p_instructor_profile_id: selectedInstructor.id,
        });

        if (error) {
          console.error('Background update failed:', error);
          return;
        }

        await refetchProfile();
      } catch (err) {
        console.error('Background update failed:', err);
      }
    }
  };

  const renderItem = useCallback(({ item, index }: { item: typeof INSTRUCTORS[0], index: number }) => {
    return <InstructorCard item={item} index={index} scrollX={scrollX} />;
  }, []);

  const onViewableItemsChanged = useCallback(({ viewableItems }: any) => {
    if (viewableItems.length > 0) {
      setCurrentIndex(viewableItems[0].index || 0);
    }
  }, []);

  return (
    <SafeAreaView style={[styles.container, { backgroundColor: theme.background }]}>
      <Stack.Screen options={{ headerShown: false }} />
      <View style={styles.header}>
        <Text style={[styles.headerTitle, { color: theme.textPrimary }]}>ESCOLHA SEU MENTOR</Text>
        <Text style={[styles.headerSubtitle, { color: theme.textSecondary }]}>
          Quem guiará sua jornada?
        </Text>
      </View>

      <Animated.FlatList
        ref={flatListRef}
        data={INSTRUCTORS}
        renderItem={renderItem}
        keyExtractor={item => item.id}
        horizontal
        pagingEnabled
        showsHorizontalScrollIndicator={false}
        onScroll={handleScroll}
        scrollEventThrottle={16}
        onViewableItemsChanged={onViewableItemsChanged}
        viewabilityConfig={{ itemVisiblePercentThreshold: 50 }}
      />

      <View style={styles.footer}>
        <View style={styles.pagination}>
          {INSTRUCTORS.map((_, idx) => (
            <View
              key={idx}
              style={[
                styles.dot,
                { backgroundColor: idx === currentIndex ? theme.primary : theme.textSecondary, opacity: idx === currentIndex ? 1 : 0.3 }
              ]}
            />
          ))}
        </View>

        <TouchableOpacity
          style={[styles.button, { backgroundColor: INSTRUCTORS[currentIndex].color }]}
          onPress={handleConfirm}
          activeOpacity={0.8}
        >
          <Text style={styles.buttonText}>ESCOLHER {INSTRUCTORS[currentIndex].name.split(' ')[1].toUpperCase()}</Text>
          <Ionicons name="arrow-forward" size={20} color="#FFF" />
        </TouchableOpacity>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  header: {
    paddingVertical: 20,
    alignItems: 'center',
  },
  headerTitle: {
    fontSize: 20,
    fontWeight: '800',
    letterSpacing: 1,
  },
  headerSubtitle: {
    fontSize: 14,
    marginTop: 4,
  },
  cardContainer: {
    width: width * 0.85,
    height: height * 0.60,
    // backgroundColor: '#1A1A1A', // Removed hardcoded
    borderRadius: 24,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    elevation: 10,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.5,
    shadowRadius: 20,
  },
  imageContainer: {
    height: '65%', // Main visual area
    width: '100%',
    backgroundColor: '#000',
  },
  instructorImage: {
    width: '100%',
    height: '100%',
  },
  badge: {
    position: 'absolute',
    bottom: 16,
    left: 16,
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 8,
  },
  badgeText: {
    color: '#FFF',
    fontSize: 12,
    fontWeight: 'bold',
    textTransform: 'uppercase',
  },
  infoContainer: {
    flex: 1,
    padding: 20,
    justifyContent: 'flex-start',
  },
  name: {
    fontSize: 22,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  traitsContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginBottom: 12,
  },
  traitTag: {
    borderWidth: 1,
    borderRadius: 100,
    paddingHorizontal: 10,
    paddingVertical: 4,
  },
  traitText: {
    fontSize: 10,
    textTransform: 'uppercase',
    fontWeight: '600',
  },
  description: {
    fontSize: 14,
    lineHeight: 20,
    opacity: 0.8,
  },
  footer: {
    height: 120, // Clean footer area
    justifyContent: 'center',
    paddingHorizontal: 24,
  },
  pagination: {
    flexDirection: 'row',
    justifyContent: 'center',
    marginBottom: 20,
    gap: 8,
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  button: {
    flexDirection: 'row',
    height: 56,
    borderRadius: 16,
    justifyContent: 'center',
    alignItems: 'center',
    gap: 12,
    shadowColor: "#000",
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 4.65,
    elevation: 8,
  },
  buttonText: {
    color: '#FFF',
    fontSize: 16,
    fontWeight: 'bold',
    letterSpacing: 1,
  },
});
