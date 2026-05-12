import { View, Text } from 'react-native';
import { useForceTheme } from '../context/ForceThemeContext';

export function InstitutionalEmpty({ text }: { text: string }) {
    const { theme } = useForceTheme();
    return (
        <View style={{ padding: 24, alignItems: 'center', flex: 1, justifyContent: 'center' }}>
            <Text style={{ textAlign: 'center', opacity: 0.7, color: theme.textSecondary, fontSize: 14 }}>{text}</Text>
        </View>
    );
}
