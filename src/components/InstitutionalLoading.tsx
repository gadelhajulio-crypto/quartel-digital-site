import { View, ActivityIndicator, Text } from 'react-native';

export function InstitutionalLoading() {
    return (
        <View style={{ padding: 24, alignItems: 'center', flex: 1, justifyContent: 'center' }}>
            <ActivityIndicator size="large" />
            <Text style={{ marginTop: 12 }}>
                Carregando dados do recruta…
            </Text>
        </View>
    );
}
