import { View, Text } from 'react-native';

export function InstitutionalError() {
    return (
        <View style={{ padding: 24, alignItems: 'center', flex: 1, justifyContent: 'center' }}>
            <Text style={{ textAlign: 'center', color: 'red' }}>
                Não foi possível carregar as informações. Tente novamente.
            </Text>
        </View>
    );
}
