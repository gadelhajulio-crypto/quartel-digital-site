export type ForceKey = 'marinha' | 'exercito' | 'aeronautica';

export const ForceThemes: Record<ForceKey, any> = {
    marinha: {
        key: 'marinha',
        label: 'Marinha do Brasil',
        icon: '⚓',

        colors: {
            primary: '#0A2A43',
            accent: '#C9A24D',
            background: '#060F18',
            card: '#0F1E2E',
            textPrimary: '#FFFFFF',
            textSecondary: '#B0BEC5',
            progress: '#C9A24D',
        },
    },

    exercito: {
        key: 'exercito',
        label: 'Exército Brasileiro',
        icon: '🪖',

        colors: {
            primary: '#2F3E1E',
            accent: '#A3B18A',
            background: '#141A10',
            card: '#1F2A16',
            textPrimary: '#FFFFFF',
            textSecondary: '#C0C7B1',
            progress: '#A3B18A',
        },
    },

    aeronautica: {
        key: 'aeronautica',
        label: 'Aeronáutica',
        icon: '✈️',

        colors: {
            primary: '#1C2B3A',
            accent: '#5DA9E9',
            background: '#0B1620',
            card: '#142536',
            textPrimary: '#FFFFFF',
            textSecondary: '#A8C6DF',
            progress: '#5DA9E9',
        },
    },
};
