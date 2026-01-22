import { View, Text } from 'react-native';

export function InstitutionalEmpty({ text }: { text: string }) {
    return (
        <View style={{ padding: 24, alignItems: 'center', flex: 1, justifyContent: 'center' }}>
            <Text style={{ textAlign: 'center', opacity: 0.7 }}>{text}</Text>
        </View>
    );
}
