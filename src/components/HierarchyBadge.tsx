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
                label: 'RECRUTA',
                icon: require('../assets/hierarchy/recruta.png'),
            };
        case 2:
            return {
                label: 'ASPIRANTE',
                icon: require('../assets/hierarchy/aspirante.png'),
            };
        case 3:
            return {
                label: 'COMBATENTE',
                icon: require('../assets/hierarchy/combatente.png'),
            };
        case 4:
            return {
                label: 'VETERANO',
                icon: require('../assets/hierarchy/veterano.png'),
            };
        case 5:
            return {
                label: 'COMANDANTE',
                icon: require('../assets/hierarchy/veterano.png'),
            };
        case 6:
            return {
                label: 'ESTRATEGISTA',
                icon: require('../assets/hierarchy/veterano.png'),
            };
        case 7:
            return {
                label: 'LENDA VIVA',
                icon: require('../assets/hierarchy/veterano.png'),
            };
        default:
            return {
                label: 'RECRUTA',
                icon: require('../assets/hierarchy/recruta.png'),
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
                    borderColor: 'rgba(255,255,255,0.1)',
                },
            ]}
        >
            <Image source={hierarchy.icon} style={styles.icon} />

            <Text style={[styles.label, { color: theme.textPrimary }]}>
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
