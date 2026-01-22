import { View, Text, StyleSheet, Image } from 'react-native';
import { useForceTheme } from '../context/ForceThemeContext';

interface HierarchyBadgeProps {
    nivelAtual: number;
}

/**
 * Mapeamento VISUAL e institucional.
 * NÃO representa regra de progressão.
 * Backend já decidiu o nivelAtual.
 */
function getHierarchyData(nivel: number) {
    switch (nivel) {
        case 1:
            return {
                label: 'Recruta',
                icon: require('../assets/hierarchy/recruta.png'),
            };
        case 2:
            return {
                label: 'Soldado',
                icon: require('../assets/hierarchy/soldado.png'),
            };
        case 3:
            return {
                label: 'Cabo',
                icon: require('../assets/hierarchy/cabo.png'),
            };
        case 4:
            return {
                label: 'Sargento',
                icon: require('../assets/hierarchy/sargento.png'),
            };
        default:
            return {
                label: 'Hierarquia não definida',
                icon: require('../assets/hierarchy/default.png'),
            };
    }
}

export function HierarchyBadge({ nivelAtual }: HierarchyBadgeProps) {
    const { theme } = useForceTheme();
    const hierarchy = getHierarchyData(nivelAtual);

    return (
        <View
            style={[
                styles.container,
                {
                    backgroundColor: theme.card,
                    borderColor: theme.border,
                },
            ]}
        >
            <Image source={hierarchy.icon} style={styles.icon} />

            <Text style={[styles.label, { color: theme.text }]}>
                {hierarchy.label}
            </Text>
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingVertical: 10,
        paddingHorizontal: 14,
        borderRadius: 8,
        borderWidth: 1,
    },
    icon: {
        width: 28,
        height: 28,
        resizeMode: 'contain',
        marginRight: 10,
    },
    label: {
        fontSize: 15,
        fontWeight: '600',
    },
});
