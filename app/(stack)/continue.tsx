import React, { useEffect } from 'react';
import { View, Text } from 'react-native';
import { useRouter } from 'expo-router';
import { useForceTheme } from '../../src/context/ForceThemeContext';

export default function ContinuarScreen() {
    const router = useRouter();
    const { theme } = useForceTheme();

    // Navegação imediata ao montar o componente
    useEffect(() => {
        // Redirecionamento forçado para o painel
        // Evita qualquer lógica de busca ou loading
        router.replace('/(tabs)/');
    }, []);

    // Renderização com mensagem intermediária para evitar tela "morta"
    const bg = theme?.background || '#000000';
    const textColor = theme?.textSecondary || '#AAAAAA';

    return (
        <View style={{ flex: 1, backgroundColor: bg, justifyContent: 'center', alignItems: 'center' }}>
            <Text style={{ color: textColor, fontSize: 16 }}>
                Redirecionando para ultima aula aberta...
            </Text>
        </View>
    );
}
