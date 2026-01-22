import React, { useEffect, useState, useRef } from 'react';
import { Slot, useRouter, useSegments, Redirect } from 'expo-router';
import { AuthProvider, useAuth } from '../src/context/AuthContext';
import { ForceThemeProvider } from '../src/context/ForceThemeContext';
import { View, ActivityIndicator } from 'react-native';
import { Asset } from 'expo-asset';
import { colors } from '../src/theme';
import { CACHED_ASSETS } from '../src/constants/assets';

/**
 * ROOT NAVIGATION GUARD
 * - Preload completo de assets
 * - Controle de autenticação
 * - Fonte única de decisão de navegação
 */

// ... imports ...

function RootLayoutNav() {
  const { session, loading } = useAuth();
  const segments = useSegments();
  const [assetsReady, setAssetsReady] = useState(false);

  // Asset Preload Effect (Unchanged)
  useEffect(() => {
    // ... (keep exact same asset logic)
    let isMounted = true;
    async function preloadAssets() {
      try {
        await Promise.all(
          CACHED_ASSETS.map(img => Asset.fromModule(img).downloadAsync())
        );
      } catch (error) {
        console.warn('[ROOT] Asset preload warning:', error);
      } finally {
        if (isMounted) setAssetsReady(true);
      }
    }
    preloadAssets();
    return () => { isMounted = false; };
  }, []);

  // 🔄 LOADING STATE
  if (loading || !assetsReady) {
    return (
      <View style={{ flex: 1, backgroundColor: colors.background, justifyContent: 'center', alignItems: 'center' }}>
        <ActivityIndicator size="large" color={colors.gold} />
      </View>
    );
  }

  // 🔒 DECLARATIVE NAVIGATION GUARD
  const inAuthGroup = segments[0] === '(auth)';

  // 1. User is logged in, but in Auth group -> Send to App
  if (session && inAuthGroup) {
    return <Redirect href="/(app)" />;
  }

  // 2. User is NOT logged in, but trying to access App -> Send to Login
  // Note: We check !inAuthGroup to prevent loop if they are already in login
  if (!session && !inAuthGroup) {
    return <Redirect href="/(auth)/login" />;
  }

  // 3. Render Content
  return <Slot />;
}

/**
 * ROOT PROVIDERS
 */
export default function RootLayout() {
  return (
    <AuthProvider>
      <ForceThemeProvider>
        <RootLayoutNav />
      </ForceThemeProvider>
    </AuthProvider>
  );
}
