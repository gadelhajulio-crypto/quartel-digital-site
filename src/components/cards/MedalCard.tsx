import { View, Text, StyleSheet } from 'react-native';
import { useForceTheme } from '../../context/ForceThemeContext';

type MedalLevel = 'none' | 'bronze' | 'silver' | 'gold';

interface MedalCardProps {
    name: string;
    description: string;
    level: MedalLevel;
    achieved: boolean;
}

export function MedalCard({
    name,
    description,
    level,
    achieved,
}: MedalCardProps) {
    const { theme } = useForceTheme();

    const levelLabel =
        level === 'gold'
            ? 'Ouro'
            : level === 'silver'
                ? 'Prata'
                : level === 'bronze'
                    ? 'Bronze'
                    : 'Não conquistada';

    const borderColor = achieved ? theme.primary : theme.border;
    const opacity = achieved ? 1 : 0.6;

    return (
        <View
            style={[
                styles.card,
                {
                    backgroundColor: theme.card,
                    borderColor,
                    opacity,
                },
            ]}
        >
            <Text style={[styles.name, { color: theme.text }]}>
                {name}
            </Text>

            <Text style={[styles.description, { color: theme.muted }]}>
                {description}
            </Text>

            <Text style={[styles.level, { color: theme.text }]}>
                Nível: {levelLabel}
            </Text>
        </View>
    );
}

const styles = StyleSheet.create({
    card: {
        padding: 16,
        borderRadius: 8,
        borderWidth: 1,
    },
    name: {
        fontSize: 16,
        fontWeight: '600',
        marginBottom: 6,
    },
    description: {
        fontSize: 13,
        marginBottom: 10,
    },
    level: {
        fontSize: 14,
        fontWeight: '500',
    },
});
