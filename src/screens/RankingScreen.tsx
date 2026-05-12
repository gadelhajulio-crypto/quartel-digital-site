import { useEffect, useState } from "react";
import {
  View,
  Text,
  StyleSheet,
  ActivityIndicator,
  FlatList,
  TouchableOpacity,
  SafeAreaView,
} from "react-native";
import { supabase } from "../lib/supabase";
import { useForceTheme } from "../context/ForceThemeContext";

type RankingItem = {
  recruta_id: string;
  nome: string;
  forca: string;
  xp_mes: number;
  posicao: number;
};

type Campeao = {
  recruta_id: string;
  forca: string;
  premiado: boolean;
};

type Props = {
  recrutaId: string;
  forca: "marinha" | "exercito" | "aeronautica";
  onVoltar: () => void;
};

export default function RankingScreen({
  recrutaId,
  forca,
  onVoltar,
}: Props) {
  const { theme } = useForceTheme(); // Use Theme
  const styles = getStyles(theme);

  const [top20, setTop20] = useState<RankingItem[]>([]);
  const [minhaPosicao, setMinhaPosicao] = useState<RankingItem | null>(null);
  const [campeoes, setCampeoes] = useState<Campeao[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function carregarDados() {
      setLoading(true);

      const { data: ranking } = await supabase
        .from("v_ranking_mensal_rcc")
        .select("*")
        .eq("forca", forca)
        .order("posicao")
        .limit(20);

      const { data: minha } = await supabase
        .from("v_posicao_recruta_mes_rcc")
        .select("*")
        .single();

      const { data: campeoesData } = await supabase
        .from("v_campeoes_mensais_rcc")
        .select("recruta_id, forca, premiado")
        .eq("forca", forca);

      setTop20((ranking ?? []) as RankingItem[]);
      setMinhaPosicao((minha as RankingItem) ?? null);
      setCampeoes((campeoesData ?? []) as Campeao[]);
      setLoading(false);
    }

    carregarDados();
  }, [recrutaId, forca]);

  function isCampeao(id: string) {
    return campeoes.some(
      (c) => c.recruta_id === id && c.premiado === true
    );
  }

  return (
    <SafeAreaView style={styles.safe}>
      <View style={styles.header}>
        <TouchableOpacity onPress={onVoltar}>
          <Text style={styles.voltar}>← Voltar</Text>
        </TouchableOpacity>
        <Text style={styles.headerTitulo}>RANKING MENSAL</Text>
        <View style={{ width: 60 }} />
      </View>

      {loading ? (
        <View style={styles.center}>
          <ActivityIndicator size="large" color={theme.accent || '#FFD166'} />
        </View>
      ) : (
        <View style={styles.container}>
          <Text style={styles.subtitulo}>
            Top 20 — {forca.toUpperCase()}
          </Text>

          <FlatList
            data={top20}
            keyExtractor={(item) => item.recruta_id}
            renderItem={({ item }) => {
              const campeao = isCampeao(item.recruta_id);

              return (
                <View
                  style={[
                    styles.item,
                    campeao && styles.campeao,
                  ]}
                >
                  <Text style={styles.posicao}>{item.posicao}º</Text>

                  <View style={{ flex: 1 }}>
                    <Text style={styles.nome}>{item.nome}</Text>
                    {campeao && (
                      <Text style={styles.badge}>🏆 CAMPEÃO</Text>
                    )}
                  </View>

                  <Text style={styles.xp}>{item.xp_mes} XP</Text>
                </View>
              );
            }}
          />

          {minhaPosicao && minhaPosicao.posicao > 20 && (
            <View style={styles.minhaPosicao}>
              <Text style={styles.minhaTitulo}>SUA COLOCAÇÃO</Text>
              <Text style={styles.minhaTexto}>
                {minhaPosicao.posicao}º lugar — {minhaPosicao.xp_mes} XP
              </Text>
            </View>
          )}
        </View>
      )}
    </SafeAreaView>
  );
}

const getStyles = (theme: any) => StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: theme.background,
  },
  center: {
    flex: 1,
    justifyContent: "center",
    alignItems: "center",
  },
  header: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: 16,
    paddingVertical: 12,
    backgroundColor: theme.background,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.05)',
  },
  headerTitulo: {
    color: theme.textPrimary,
    fontSize: 18,
    fontWeight: "bold",
  },
  voltar: {
    color: theme.secondary || "#38BDF8",
    fontSize: 16,
  },
  container: {
    flex: 1,
    padding: 16,
  },
  subtitulo: {
    color: theme.textSecondary,
    textAlign: "center",
    marginBottom: 12,
  },
  item: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: theme.card,
    padding: 12,
    borderRadius: 6,
    marginBottom: 8,
  },
  campeao: {
    borderWidth: 1,
    borderColor: theme.accent || "#FACC15",
  },
  posicao: {
    color: theme.accent || "#FACC15",
    fontWeight: "bold",
    width: 40,
  },
  nome: {
    color: theme.textPrimary,
    fontSize: 16,
  },
  badge: {
    color: theme.accent || "#FACC15",
    fontSize: 12,
    marginTop: 2,
  },
  xp: {
    color: theme.success || "#22C55E",
    fontWeight: "bold",
  },
  minhaPosicao: {
    marginTop: 16,
    padding: 12,
    borderRadius: 6,
    backgroundColor: theme.card,
    borderWidth: 1,
    borderColor: theme.border,
  },
  minhaTitulo: {
    color: theme.textSecondary,
    fontSize: 12,
    marginBottom: 4,
  },
  minhaTexto: {
    color: theme.textPrimary,
    fontSize: 16,
    fontWeight: "bold",
  },
});
