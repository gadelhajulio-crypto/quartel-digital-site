import { useEffect, useState } from "react";
import {
  View,
  Text,
  StyleSheet,
  ActivityIndicator,
  TouchableOpacity,
  Alert,
  ScrollView,
} from "react-native";
import { supabase } from "../lib/supabase";
import RankingScreen from "./RankingScreen";

type Props = {
  recrutaId: string;
};

type Recruta = {
  nome: string;
  forca: "marinha" | "exercito" | "aeronautica";
  patente: string;
  xp: number;
};

export default function PainelScreen({ recrutaId }: Props) {
  const [recruta, setRecruta] = useState<Recruta | null>(null);
  const [loading, setLoading] = useState(true);
  const [verRanking, setVerRanking] = useState(false);

  useEffect(() => {
    async function carregarRecruta() {
      setLoading(true);

      const { data, error } = await supabase
        .from("v_identidade_recruta")
        .select("nome, forca, patente, xp")
        .eq("auth_id", recrutaId)
        .single();

      if (error) {
        console.error("Erro ao carregar recruta:", error);
        setLoading(false);
        return;
      }

      setRecruta(data as Recruta);
      setLoading(false);
    }

    carregarRecruta();
  }, [recrutaId]);

  async function handleLogout() {
    Alert.alert("Sair", "Deseja realmente encerrar a sessão?", [
      { text: "Cancelar", style: "cancel" },
      {
        text: "Sair",
        style: "destructive",
        onPress: async () => {
          await supabase.auth.signOut();
        },
      },
    ]);
  }

  // 🔹 TELA DE RANKING
  if (verRanking && recruta) {
    return (
      <RankingScreen
        recrutaId={recrutaId}
        forca={recruta.forca}
        onVoltar={() => setVerRanking(false)}
      />
    );
  }

  if (loading) {
    return (
      <View style={styles.center}>
        <ActivityIndicator size="large" color="#FFFFFF" />
      </View>
    );
  }

  if (!recruta) {
    return (
      <View style={styles.center}>
        <Text style={styles.erro}>Erro ao carregar dados do recruta</Text>
      </View>
    );
  }

  return (
    <ScrollView style={styles.container}>
      <Text style={styles.titulo}>PAINEL DO RECRUTA</Text>

      <View style={styles.card}>
        <Text style={styles.label}>Nome</Text>
        <Text style={styles.valor}>{recruta.nome}</Text>

        <Text style={styles.label}>Força</Text>
        <Text style={styles.valor}>{recruta.forca.toUpperCase()}</Text>

        <Text style={styles.label}>Patente</Text>
        <Text style={styles.valor}>{recruta.patente}</Text>

        <Text style={styles.label}>XP Total</Text>
        <Text style={styles.valor}>{recruta.xp}</Text>
      </View>

      {/* BOTÃO VER RANKING */}
      <TouchableOpacity
        style={styles.botaoRanking}
        onPress={() => setVerRanking(true)}
      >
        <Text style={styles.botaoTexto}>VER RANKING MENSAL</Text>
      </TouchableOpacity>

      {/* BOTÃO SAIR */}
      <TouchableOpacity
        style={styles.botaoLogout}
        onPress={handleLogout}
      >
        <Text style={styles.botaoTexto}>SAIR</Text>
      </TouchableOpacity>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  center: {
    flex: 1,
    backgroundColor: "#0F172A",
    justifyContent: "center",
    alignItems: "center",
  },
  container: {
    flex: 1,
    backgroundColor: "#0F172A",
    padding: 24,
  },
  titulo: {
    fontSize: 24,
    fontWeight: "bold",
    color: "#FFFFFF",
    textAlign: "center",
    marginBottom: 16,
  },
  card: {
    backgroundColor: "#1E293B",
    borderRadius: 8,
    padding: 16,
    marginBottom: 24,
  },
  label: {
    color: "#94A3B8",
    fontSize: 14,
    marginTop: 12,
  },
  valor: {
    color: "#FFFFFF",
    fontSize: 18,
    fontWeight: "bold",
  },
  botaoRanking: {
    backgroundColor: "#1E293B",
    paddingVertical: 14,
    borderRadius: 6,
    marginBottom: 12,
  },
  botaoLogout: {
    backgroundColor: "#991B1B",
    paddingVertical: 14,
    borderRadius: 6,
  },
  botaoTexto: {
    color: "#FFFFFF",
    fontSize: 16,
    fontWeight: "bold",
    textAlign: "center",
  },
  erro: {
    color: "#F87171",
  },
});
