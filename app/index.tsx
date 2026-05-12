import { View } from 'react-native';

// Rota inicial do Expo Router ("/").
// O BootstrapGate em _layout.tsx assume o controle do redirecionamento via overlay.
// Esta tela permanece invisível sob o overlay de loading/splash.
export default function Index() {
  return <View style={{ flex: 1, backgroundColor: '#0F0F13' }} />;
}
