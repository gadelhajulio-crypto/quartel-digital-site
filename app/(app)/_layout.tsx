import React, { useEffect } from 'react';
import { Tabs, useRouter, usePathname, Redirect } from 'expo-router';
import { useForceTheme } from '../../src/context/ForceThemeContext';
import { View, ActivityIndicator } from 'react-native';
import BottomBar from '../../src/components/navigation/BottomBar';
import { useAuth } from '../../src/context/AuthContext';
import { InstitutionalLoading } from '../../src/components/InstitutionalLoading';

function ProtectedLayoutContent() {
  const { theme, loading: themeLoading } = useForceTheme();
  const { session, profile, loading: authLoading } = useAuth();
  const router = useRouter();
  const pathname = usePathname();

  // 2. Instructor Guard (Moved UP to respect Hook Rules)
  useEffect(() => {
    if (authLoading || themeLoading || !profile) return;

    const isSelecting = pathname.includes('/instructor-select');

    if (!profile.instructor_profile_id && !isSelecting) {
      console.log('[LAYOUT] Missing instructor. Redirecting to selection.');
      router.replace('/(onboarding)/instructor-select');
    }
  }, [profile, authLoading, themeLoading, pathname]);

  // 1. Session Guard
  if (authLoading) {
    return <InstitutionalLoading />;
  }

  if (!session) {
    return <Redirect href="/auth" />;
  }

  if (themeLoading) {
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
      <Tabs.Screen name="continuar" />
      <Tabs.Screen name="instrutor/selecionar" options={{ href: null, tabBarStyle: { display: 'none' } }} />
      <Tabs.Screen name="ranking" options={{ href: null }} />
      <Tabs.Screen name="perfil/index" options={{ href: null, tabBarStyle: { display: 'none' } }} />
      <Tabs.Screen name="aulas" options={{ href: null }} />
      <Tabs.Screen name="chat" options={{ href: null }} />
    </Tabs>
  );
}

export default function ProtectedLayout() {
  return <ProtectedLayoutContent />;
}
