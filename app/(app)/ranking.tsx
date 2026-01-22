import React from 'react';
import { View, Text, StyleSheet, FlatList, ActivityIndicator } from 'react-native';
import { useRankingList, RankingItem } from '../../src/hooks/useRankingList';
import { useAuth } from '../../src/context/AuthContext';
import { useForceTheme } from '../../src/context/ForceThemeContext';
import { Header } from '../../src/components/Header';

export default function RankingScreen() {
    const { session, profile } = useAuth();
    const userId = session?.user?.id;
    const userForce = profile?.forca || 'marinha';

    const { theme } = useForceTheme(); // Dynamic Theme
    const styles = getStyles(theme);

    const { rankingList, loading } = useRankingList(userForce);

    if (loading) {
        return (
            <View style={[styles.container, styles.center]}>
                <ActivityIndicator size="large" color={theme.accent || '#FFD166'} />
            </View>
        );
    }

    const renderItem = ({ item }: { item: RankingItem }) => {
        const isCurrentUser = item.user_id === userId;
        // Display logic: prefer war_name, then full_name, then 'Recruta'
        const name = item.profiles?.war_name || item.profiles?.full_name || item.profiles?.name || 'Recruta';

        return (
            <View style={[styles.itemContainer, isCurrentUser && styles.currentUserItem]}>
                <View style={styles.left}>
                    <Text style={[styles.rank, isCurrentUser && styles.currentUserText]}>
                        {item.rank_position}º
                    </Text>
                    <View>
                        <Text style={[styles.name, isCurrentUser && styles.currentUserText]}>
                            {isCurrentUser ? `${name} (Você)` : name}
                        </Text>
                    </View>
                </View>
                <Text style={[styles.xp, isCurrentUser && styles.currentUserText]}>
                    {item.xp_mensal} XP
                </Text>
            </View>
        );
    };

    return (
        <View style={styles.container}>
            <Header title="RANKING MENSAL" />
            <FlatList
                data={rankingList}
                renderItem={renderItem}
                keyExtractor={(item) => item.user_id + '_' + item.rank_position}
                contentContainerStyle={styles.listContent}
                ListEmptyComponent={
                    <View style={styles.center}>
                        <Text style={styles.emptyText}>Ranking ainda não consolidado para este mês.</Text>
                    </View>
                }
            />
            <Text style={styles.footer}>
                Atualizado automaticamente • Top 50 da Força
            </Text>
        </View>
    );
}

const getStyles = (theme: any) => StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: theme.background,
    },
    center: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
    },
    listContent: {
        padding: 16,
    },
    itemContainer: {
        flexDirection: 'row',
        justifyContent: 'space-between',
        alignItems: 'center',
        paddingVertical: 12,
        paddingHorizontal: 16,
        marginBottom: 8,
        backgroundColor: theme.card,
        borderRadius: 8,
    },
    currentUserItem: {
        backgroundColor: 'rgba(201, 162, 77, 0.15)', // Discrete gold tint
        borderWidth: 1,
        borderColor: 'rgba(201, 162, 77, 0.3)',
    },
    left: {
        flexDirection: 'row',
        alignItems: 'center',
        gap: 16,
    },
    rank: {
        fontSize: 18,
        fontWeight: 'bold',
        color: theme.textSecondary,
        width: 30, // Fixed width for alignment
        textAlign: 'center',
    },
    name: {
        fontSize: 16,
        color: theme.textPrimary,
    },
    xp: {
        fontSize: 16,
        fontWeight: 'bold',
        color: theme.accent || '#FFD166',
    },
    currentUserText: {
        color: theme.accent || '#FFD166',
        fontWeight: 'bold',
    },
    emptyText: {
        color: theme.textSecondary,
        marginTop: 20,
    },
    footer: {
        textAlign: 'center',
        padding: 12,
        color: theme.textSecondary,
        fontSize: 12,
        opacity: 0.6,
    }
});
