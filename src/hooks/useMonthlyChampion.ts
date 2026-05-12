// ranking mensal bloqueado pelo C6
// Campeão mensal desabilitado temporariamente até implantação da view canônica.

export interface ChampionData {
    recruta_id: string;
    forca: string;
    month_ref: string;
    profiles: {
        full_name?: string;
        name?: string;
        war_name?: string;
    } | null;
}

export function useMonthlyChampion(_userForce: string) {
    return { champion: null as ChampionData | null, loading: false };
}
