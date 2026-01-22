import React, { useEffect, useState } from 'react';
import { View, Text, ActivityIndicator, Alert } from 'react-native';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { supabase } from '../../../../../src/lib/supabase';
import { useAuth } from '../../../../../src/context/AuthContext';
import { useForceTheme } from '../../../../../src/context/ForceThemeContext'; // Dynamic hook
import ReviewScreen from '../../../../../src/screens/ReviewScreen';
import { canAccessModule } from '../../../../../src/utils/canAccessModule';

export default function ReviewRoute() {
    const { id, revisaoId } = useLocalSearchParams();
    const { profile } = useAuth();
    const router = useRouter();
    const { theme } = useForceTheme(); // Dynamic Theme

    const [reviewData, setReviewData] = useState<any>(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        if (id && revisaoId && profile) {
            loadReview();
        }
    }, [id, revisaoId, profile]);

    const loadReview = async () => {
        try {
            setLoading(true);

            // 1. Check Module Access First
            const { data: moduleData, error: moduleError } = await supabase
                .from('modulos')
                .select('id, is_degustacao')
                .eq('id', id)
                .single();

            if (moduleError || !moduleData) throw new Error('Módulo não encontrado');

            if (!canAccessModule(profile!, moduleData)) {
                Alert.alert('Acesso Restrito', 'Você não tem permissão para acessar esta revisão.');
                router.back();
                return;
            }

            // 2. Fetch Review Data
            const { data, error } = await supabase
                .from('revisoes')
                .select('*')
                .eq('id', revisaoId)
                .single();

            if (error) throw error;
            setReviewData(data);

        } catch (err) {
            console.error('Error loading review:', err);
            Alert.alert('Erro', 'Não foi possível carregar a revisão.');
            router.back();
        } finally {
            setLoading(false);
        }
    };

    if (loading) {
        return (
            <View style={{ flex: 1, backgroundColor: theme.background, justifyContent: 'center', alignItems: 'center' }}>
                <ActivityIndicator color={theme.accent || '#FFD166'} />
            </View>
        );
    }

    return (
        <ReviewScreen revisao={reviewData} />
    );
}
