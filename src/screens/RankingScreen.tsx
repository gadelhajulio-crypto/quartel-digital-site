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
  const [top20, setTop20] = useState<RankingItem[]>([]);
  const [minhaPosicao, setMinhaPosicao] = useState<RankingItem | null>(null);
  const [campeoes, setCampeoes] = useState<Campeao[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function carregarDados() {
      setLoading(true);

      const { data: ranking } = await supabase
        .from("vw_ranking_mensal")
        .select("*")
        .eq("forca", forca)
        .order("posicao")
        .limit(20);

      const { data: minha } = await supabase
        .from("vw_posicao_recruta_mes")
        .select("*")
        .eq("recruta_id", recrutaId)
        .single();

      const { data: campeoesData } = await supabase
        .from("campeoes_mensais")
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
          <ActivityIndicator size="large" color="#FFFFFF" />
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

const styles = StyleSheet.create({
  safe: {
    flex: 1,
    backgroundColor: "#0F172A",
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
    backgroundColor: "#020617",
  },
  headerTitulo: {
    color: "#FFFFFF",
    fontSize: 18,
    fontWeight: "bold",
  },
  voltar: {
    color: "#38BDF8",
    fontSize: 16,
  },
  container: {
    flex: 1,
    padding: 16,
  },
  subtitulo: {
    color: "#94A3B8",
    textAlign: "center",
    marginBottom: 12,
  },
  item: {
    flexDirection: "row",
    alignItems: "center",
    backgroundColor: "#020617",
    padding: 12,
    borderRadius: 6,
    marginBottom: 8,
  },
  campeao: {
    borderWidth: 1,
    borderColor: "#FACC15",
  },
  posicao: {
    color: "#FACC15",
    fontWeight: "bold",
    width: 40,
  },
  nome: {
    color: "#FFFFFF",
    fontSize: 16,
  },
  badge: {
    color: "#FACC15",
    fontSize: 12,
    marginTop: 2,
  },
  xp: {
    color: "#22C55E",
    fontWeight: "bold",
  },
  minhaPosicao: {
    marginTop: 16,
    padding: 12,
    borderRadius: 6,
    backgroundColor: "#1E293B",
  },
  minhaTitulo: {
    color: "#94A3B8",
    fontSize: 12,
    marginBottom: 4,
  },
  minhaTexto: {
    color: "#FFFFFF",
    fontSize: 16,
    fontWeight: "bold",
  },
});
