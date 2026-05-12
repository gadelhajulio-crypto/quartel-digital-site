import { View, Text, StyleSheet } from 'react-native';
import { useForceTheme } from '../../../src/context/ForceThemeContext';
import { InstitutionalEmpty } from '../../../src/components/InstitutionalEmpty';
import { SafeAreaView } from 'react-native-safe-area-context';

export default function RevisoesScreen() {
    const { theme } = useForceTheme();

    return (
        <SafeAreaView style={[styles.container, { backgroundColor: theme.background }]}>
            {/* Header institucional */}
            <Text style={[styles.header, { color: theme.textPrimary }]}>
                Revisões Disponíveis
            </Text>

            <View style={styles.content}>
                <InstitutionalEmpty text="Nenhuma revisão disponível no momento." />
            </View>
        </SafeAreaView>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        padding: 16,
    },
    header: {
        fontSize: 20,
        fontWeight: '600',
        marginBottom: 16,
    },
    content: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
        marginTop: -50, // Visual adjustment
    },
});
