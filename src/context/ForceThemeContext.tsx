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
        surface: 'rgba(0,0,0,0.3)', // Dark overlay
        border: 'rgba(255,255,255,0.1)',
        textMuted: '#767577',
        primarySoft: 'rgba(201, 162, 77, 0.15)', // Gold tint
        text: '#FFFFFF',
        muted: '#767577',
        error: '#C94A4A',
        success: '#2D6A4F',
        dashboard: {
            background: '#F5F7FA',
            card: '#FFFFFF',
            textPrimary: '#0A2540',
            textSecondary: '#6C849A',
            accent: '#003366',
            border: 'rgba(0,0,0,0.05)',
            headerOverlay: 'rgba(255,255,255,0.85)',
        }
    },
    exercito: {
        background: '#0B140C',
        primary: '#1E4620',
        secondary: '#3A6B35',
        accent: '#FFD166',
        textPrimary: '#FFFFFF',
        textSecondary: '#AAB8C2',
        card: '#142514',
        surface: 'rgba(0,0,0,0.3)',
        border: 'rgba(255,255,255,0.1)',
        textMuted: '#767577',
        primarySoft: 'rgba(201, 162, 77, 0.15)',
        text: '#FFFFFF',
        muted: '#767577',
        error: '#C94A4A',
        success: '#2D6A4F',
        dashboard: {
            background: '#F5F7FA',
            card: '#FFFFFF',
            textPrimary: '#1E4620',
            textSecondary: '#5A6C58',
            accent: '#283618',
            border: 'rgba(0,0,0,0.05)',
            headerOverlay: 'rgba(255,255,255,0.85)',
        }
    },
    aeronautica: {
        background: '#020812',
        primary: '#003A8F',
        secondary: '#4DA3FF',
        accent: '#FFD166',
        textPrimary: '#FFFFFF',
        textSecondary: '#AAB8C2',
        card: '#0A1A2F',
        surface: 'rgba(0,0,0,0.3)',
        border: 'rgba(255,255,255,0.1)',
        textMuted: '#767577',
        primarySoft: 'rgba(201, 162, 77, 0.15)',
        text: '#FFFFFF',
        muted: '#767577',
        error: '#C94A4A',
        success: '#2D6A4F',
        dashboard: {
            background: '#F5F7FA',
            card: '#FFFFFF',
            textPrimary: '#0A1A2F',
            textSecondary: '#718096',
            accent: '#003A8F',
            border: 'rgba(0,0,0,0.05)',
            headerOverlay: 'rgba(255,255,255,0.85)',
        }
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
    // UX Tokens
    surface: string;
    border: string;
    textMuted: string;
    primarySoft: string;
    // Aliases usados pelos componentes
    text: string;
    muted: string;
    error: string;
    success: string;
    // Dashboard Specific
    dashboard: {
        background: string;
        card: string;
        textPrimary: string;
        textSecondary: string;
        accent: string;
        border: string;
        headerOverlay: string;
    }
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
            // Logout ou estado inicial: volta para o tema padrão
            setTheme(THEMES.marinha);
            setForce('marinha');
            setLoading(false);
            return;
        }

        loadForceTheme(profile.forca);
    }, [profile?.forca]);

    function applyFallback(forca: string) {
        setTheme(THEMES[forca] || THEMES.marinha);
        setForce(forca);
    }

    async function loadForceTheme(forca: string) {
        try {
            const { data, error } = await supabase
                .from('v_forcas_theme')
                .select('cor_primaria, cor_secundaria, cor_fundo')
                .eq('id', forca)
                .single();

            if (error || !data) {
                console.warn('[ForceTheme] Fallback theme for:', forca);
                applyFallback(forca);
                return;
            }

            setTheme({
                background: data.cor_fundo,
                primary: data.cor_primaria,
                secondary: data.cor_secundaria,
                accent: THEMES[forca]?.accent ?? '#FFD166',
                textPrimary: THEMES[forca]?.textPrimary ?? '#FFFFFF',
                textSecondary: THEMES[forca]?.textSecondary ?? '#AAB8C2',
                card: THEMES[forca]?.card ?? '#111111',
                surface: THEMES[forca]?.surface ?? 'rgba(0,0,0,0.3)',
                border: THEMES[forca]?.border ?? 'rgba(255,255,255,0.1)',
                textMuted: THEMES[forca]?.textMuted ?? '#767577',
                primarySoft: THEMES[forca]?.primarySoft ?? 'rgba(201, 162, 77, 0.15)',
                text: THEMES[forca]?.textPrimary ?? '#FFFFFF',
                muted: THEMES[forca]?.textMuted ?? '#767577',
                error: '#C94A4A',
                success: '#2D6A4F',
                dashboard: THEMES[forca]?.dashboard ?? THEMES.marinha.dashboard,
            });

            setForce(forca);
        } catch (e) {
            console.warn('[ForceTheme] Exception, fallback used', e);
            applyFallback(forca);
        } finally {
            setLoading(false);
        }
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
