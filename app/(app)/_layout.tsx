import React, { useEffect } from 'react';
import { Tabs, useRouter, usePathname } from 'expo-router';
import { useForceTheme } from '../../src/context/ForceThemeContext';
import { View, ActivityIndicator, Platform } from 'react-native';
import BottomBar from '../../src/components/navigation/BottomBar';
import { useAuth } from '../../src/context/AuthContext';

function ProtectedLayoutContent() {
  const { theme, loading: themeLoading } = useForceTheme();
  const { profile, loading: authLoading } = useAuth();
  const router = useRouter();
  const pathname = usePathname();

  // 🔒 REDIRECT LOGIC: Force Instructor Selection
  useEffect(() => {
    if (authLoading || themeLoading || !profile) return;

    const isSelecting = pathname.includes('/instructor-select'); // Check new path

    // If user has no instructor selected and is NOT on selection screen, redirect
    if (!profile.instructor_profile_id && !isSelecting) {
      console.log('[LAYOUT] Missing instructor. Redirecting to selection.');
      router.replace('/(onboarding)/instructor-select');
    }
  }, [profile, authLoading, themeLoading, pathname]);

  if (themeLoading || authLoading) {
    return (
      <View style={{ flex: 1, backgroundColor: '#000', justifyContent: 'center', alignItems: 'center' }}>
        <ActivityIndicator size="large" color="#FFD700" />
      </View>
    );
  }

  return (
    <Tabs
      screenOptions={{
        headerShown: false,
      }}
      tabBar={(props) => <BottomBar />}
    >
      <Tabs.Screen name="index" />
      <Tabs.Screen name="instrutor/index" />

      {/* New Route: Continuar */}
      <Tabs.Screen name="continuar" />

      {/* Removed: perfil/index */}

      {/* Hidden Routes */}
      <Tabs.Screen name="instrutor/selecionar" options={{ href: null, tabBarStyle: { display: 'none' } }} />
      <Tabs.Screen name="ranking" options={{ href: null }} />
      <Tabs.Screen name="perfil/index" options={{ href: null, tabBarStyle: { display: 'none' } }} />

      <Tabs.Screen name="aulas" options={{ href: null }} />
      <Tabs.Screen name="chat" options={{ href: null }} />
    </Tabs>
  );
}

export default function ProtectedLayout() {
  // ThemeProvider is removed because ForceThemeProvider is likely in Root Layout
  return (
    <ProtectedLayoutContent />
  );
}
