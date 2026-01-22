import React, { createContext, useContext, useEffect, useState } from 'react';
import { supabase } from '../lib/supabase';
import { useAuth } from './AuthContext';

const THEMES: Record<string, Theme> = {
    marinha: {
        background: '#020B14',
        primary: '#0A2540',
        secondary: '#1B4F72',
        accent: '#FFD166',
        textPrimary: '#FFFFFF',
        textSecondary: '#AAB8C2',
        card: '#0F1E2E',
    },
    exercito: {
        background: '#0B140C',
        primary: '#1E4620',
        secondary: '#3A6B35',
        accent: '#FFD166',
        textPrimary: '#FFFFFF',
        textSecondary: '#AAB8C2',
        card: '#142514',
    },
    aeronautica: {
        background: '#020812',
        primary: '#003A8F',
        secondary: '#4DA3FF',
        accent: '#FFD166',
        textPrimary: '#FFFFFF',
        textSecondary: '#AAB8C2',
        card: '#0A1A2F',
    },
};

type Theme = {
    background: string;
    primary: string;
    secondary: string;
    accent: string;
    textPrimary: string;
    textSecondary: string;
    card: string;
};

type ForceThemeContextType = {
    theme: Theme;
    force: string;
    loading: boolean;
};

const ForceThemeContext = createContext<ForceThemeContextType>({
    theme: THEMES.marinha,
    force: 'marinha',
    loading: true,
});

export function ForceThemeProvider({ children }: { children: React.ReactNode }) {
    const { profile } = useAuth();

    const [theme, setTheme] = useState<Theme>(THEMES.marinha);
    const [force, setForce] = useState<string>('marinha');
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        if (!profile?.forca) {
            // Logic for logout or initial state: reset to default
            if (force !== 'marinha') {
                applyFallback('marinha');
            }
            setLoading(false);
            return;
        }

        loadForceTheme(profile.forca);
    }, [profile?.forca]);

    async function loadForceTheme(forca: string) {
        try {
            const { data, error } = await supabase
                .from('forcas')
                .select('cor_primaria, cor_secundaria, cor_fundo')
                .eq('id', forca)
                .single();

            if (error || !data) {
                console.warn('[ForceTheme] Fallback theme for:', forca);
                applyFallback(forca);
                return;
            }

            console.log(`🎨 TEMA DINÂMICO APLICADO: ${forca}`);

            setTheme({
                background: data.cor_fundo,
                primary: data.cor_primaria,
                secondary: data.cor_secundaria,
                accent: THEMES[forca]?.accent ?? '#FFD166',
                textPrimary: THEMES[forca]?.textPrimary ?? '#FFFFFF',
                textSecondary: THEMES[forca]?.textSecondary ?? '#AAB8C2',
                card: THEMES[forca]?.card ?? '#111111',
            });

            setForce(forca);
        } catch (e) {
            console.warn('[ForceTheme] Exception, fallback used', e);
            applyFallback(forca);
        } finally {
            setLoading(false);
        }
    }

    function applyFallback(forca: string) {
        setTheme(THEMES[forca] || THEMES.marinha);
        setForce(forca);
    }

    return (
        <ForceThemeContext.Provider value={{ theme, force, loading }}>
            {children}
        </ForceThemeContext.Provider>
    );
}

export function useForceTheme() {
    return useContext(ForceThemeContext);
}
