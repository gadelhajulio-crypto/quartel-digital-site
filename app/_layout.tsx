import { Slot } from 'expo-router';
import { AuthProvider } from '../src/context/AuthContext';
import { ForceThemeProvider } from '../src/context/ForceThemeContext';

export default function RootLayout() {
  return (
    <AuthProvider>
      <ForceThemeProvider>
        <Slot />
      </ForceThemeProvider>
    </AuthProvider>
  );
}
