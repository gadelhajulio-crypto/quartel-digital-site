import { Slot, useRouter } from 'expo-router';
import { useEffect } from 'react';
import { View } from 'react-native';
import * as Notifications from 'expo-notifications';
import { AuthProvider } from '../src/context/AuthContext';
import { ForceThemeProvider } from '../src/context/ForceThemeContext';
import { ErrorBoundary } from '../src/components/ErrorBoundary';
import { InstitutionalEventProvider } from '../src/context/InstitutionalEventContext';
import { InstitutionalEventRenderer } from '../src/components/events/InstitutionalEventRenderer';
import { startAppLockGuardian, updateLastActive } from '../src/auth/appLockGuardian';
import { startAuthForegroundCoordinator } from '../src/auth/authForegroundCoordinator';
import { BootstrapGate } from '../src/components/navigation/BootstrapGate';

export default function RootLayout() {
  const router = useRouter();

  useEffect(() => {
    startAppLockGuardian();
    startAuthForegroundCoordinator();

    // Toque em notificação push — navega para a conversa ou para a tab chat
    const subscription = Notifications.addNotificationResponseReceivedListener(
      (response) => {
        const data = response.notification.request.content.data as
          | { type?: string; conversa_id?: string }
          | undefined;
        if (data?.type === 'chat_reply') {
          router.push('/(tabs)/chat' as any);
        }
      },
    );

    return () => subscription.remove();
  }, [router]);

  return (
    <View style={{ flex: 1 }} onTouchStart={updateLastActive}>
      <ErrorBoundary>
        <AuthProvider>
          <ForceThemeProvider>
            <InstitutionalEventProvider>
              <BootstrapGate>
                <Slot />
              </BootstrapGate>
              <InstitutionalEventRenderer />
            </InstitutionalEventProvider>
          </ForceThemeProvider>
        </AuthProvider>
      </ErrorBoundary>
    </View>
  );
}
