export type ForceTheme = {
  primary: string;
  secondary: string;
  background: string;
  surface: string;
  text: string;
  locked: string;
  success: string;
  warning: string;
  // Button Colors
  btnPrimary: string;
  btnSecondary: string;
  // Dashboard Specific (Light Theme)
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

// Faithful Palette Definition (Updated per Spec)
export const colors = {
  background: '#0B1C2D',
  card: '#112A3F',
  border: '#1E3A52',
  textPrimary: '#FFFFFF',
  textSecondary: '#9FB3C8',
  placeholder: '#6C849A',
  gold: '#C9A24D',
  disabled: '#3A4F63',
  error: '#C94A4A',
  // Backward compatibility aliases
  surface: '#112A3F',
  text: '#FFFFFF',
  oliveIntense: '#0B1C2D',
  graphite: '#112A3F',
  navyBack: '#0B1C2D',
  navySurf: '#112A3F',
  airBack: '#1F2A38',
  airSurf: '#2C3E50',
  airSilver: '#B0C4DE',
  // Required by legacy theme structure
  oliveGreen: '#112A3F',
  matteBlack: '#0B1C2D',
  white: '#FFFFFF',
  btnPrimary: '#C9A24D',
  btnSecondary: '#112A3F',
  primary: '#C9A24D',
  secondary: '#C9A24D',
  cardSecondary: '#1C1C1C',
  muted: '#2A2A2A',
  black: '#000000',
  success: '#2D6A4F',
  warning: '#B7950B',
  locked: 'rgba(0,0,0,0.5)',
};

export const typography = {
  regular: 'Inter_400Regular',
  medium: 'Inter_500Medium',
  semiBold: 'Inter_600SemiBold',
  bold: 'Inter_700Bold',
};

export const theme = {
  colors: {
    ...colors,
  },
  forces: {
    army: {
      primary: colors.gold,
      secondary: colors.gold,
      background: colors.background,
      surface: colors.card,
      text: colors.textPrimary,
      locked: colors.locked,
      success: colors.success,
      warning: colors.warning,
      btnPrimary: colors.gold,
      btnSecondary: colors.card,
      dashboard: {
        background: '#F5F7FA',
        card: '#FFFFFF',
        textPrimary: '#1E4620', // Army Green Dark
        textSecondary: '#5A6C58',
        accent: '#283618', // Army Strong Green
        border: 'rgba(0,0,0,0.05)',
        headerOverlay: 'rgba(255,255,255,0.85)',
      }
    },
    navy: {
      primary: colors.gold,
      secondary: colors.gold,
      background: '#0B1C2D',
      surface: '#112A3F',
      text: colors.textPrimary,
      locked: colors.locked,
      success: colors.success,
      warning: colors.warning,
      btnPrimary: colors.card,
      btnSecondary: colors.disabled,
      dashboard: {
        background: '#F5F7FA',
        card: '#FFFFFF',
        textPrimary: '#0A2540', // Navy Dark
        textSecondary: '#6C849A',
        accent: '#003366', // Naval Blue
        border: 'rgba(0,0,0,0.05)',
        headerOverlay: 'rgba(255,255,255,0.85)',
      }
    },
    airforce: {
      primary: '#B0C4DE',
      secondary: colors.gold,
      background: '#1F2A38',
      surface: '#2C3E50',
      text: colors.textPrimary,
      locked: colors.locked,
      success: colors.success,
      warning: colors.warning,
      btnPrimary: '#2C3E50',
      btnSecondary: colors.disabled,
      dashboard: {
        background: '#F5F7FA',
        card: '#FFFFFF',
        textPrimary: '#0A1A2F',
        textSecondary: '#718096',
        accent: '#003A8F', // Airforce Blue
        border: 'rgba(0,0,0,0.05)',
        headerOverlay: 'rgba(255,255,255,0.85)',
      }
    }
  },
  spacing: {
    s: 8,
    m: 16,
    l: 24,
    xl: 32,
  },
  typography: {
    header: {
      fontSize: 24,
      fontWeight: '700',
      color: colors.gold,
      textTransform: 'uppercase',
      letterSpacing: 2,
    },
    body: {
      fontSize: 16,
      color: colors.textPrimary,
    },
    uppercaseBold: {
      fontWeight: '700',
      textTransform: 'uppercase',
      letterSpacing: 1,
    }
  },
  borderRadius: 12,
};

export function getThemeByForce(force: 'army' | 'navy' | 'airforce' | string): ForceTheme {
  const key = force as keyof typeof theme.forces;
  return theme.forces[key] || theme.forces.army;
}
