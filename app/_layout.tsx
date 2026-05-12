import { Slot } from 'expo-router';
import { useEffect } from 'react';
import { View } from 'react-native';
import { AuthProvider } from '../src/context/AuthContext';
import { ForceThemeProvider } from '../src/context/ForceThemeContext';
import { ErrorBoundary } from '../src/components/ErrorBoundary';
import { InstitutionalEventProvider } from '../src/context/InstitutionalEventContext';
import { InstitutionalEventRenderer } from '../src/components/events/InstitutionalEventRenderer';
import { startAppLockGuardian, updateLastActive } from '../src/auth/appLockGuardian';
import { startAuthForegroundCoordinator } from '../src/auth/authForegroundCoordinator';
import { BootstrapGate } from '../src/components/navigation/BootstrapGate';

export default function RootLayout() {
  useEffect(() => {
    startAppLockGuardian();
    startAuthForegroundCoordinator();
  }, []);

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
