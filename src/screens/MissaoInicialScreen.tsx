import { useEffect, useState } from "react";
import { View, Text, StyleSheet, TouchableOpacity } from "react-native";
import { supabase } from "../lib/supabase";

type Props = {
  recrutaId: string;
  onFinalizar: () => void;
};

export default function MissaoInicialScreen({ recrutaId, onFinalizar }: Props) {
  const [concluida, setConcluida] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    async function concluirMissao() {
      const { error } = await supabase.rpc("concluir_missao_inicial", {
        p_recruta_id: recrutaId,
      });

      if (error) {
        setErro(error.message);
      } else {
        setConcluida(true);
      }
    }

    concluirMissao();
  }, [recrutaId]);

  if (erro) {
    return (
      <View style={styles.container}>
        <Text style={styles.texto}>Erro: {erro}</Text>
      </View>
    );
  }

  if (!concluida) {
    return (
      <View style={styles.container}>
        <Text style={styles.texto}>Concluindo missão...</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Text style={styles.titulo}>MISSÃO CONCLUÍDA</Text>

      <Text style={styles.texto}>
        Você completou a instrução inicial.
        {"\n"}Seu progresso foi registrado.
      </Text>

      <Text style={styles.xp}>+50 XP</Text>

      <TouchableOpacity style={styles.botao} onPress={onFinalizar}>
        <Text style={styles.botaoTexto}>IR PARA O PAINEL</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#0F172A",
    justifyContent: "center",
    alignItems: "center",
    padding: 24,
  },
  titulo: {
    fontSize: 28,
    fontWeight: "bold",
    color: "#FFFFFF",
    marginBottom: 16,
  },
  texto: {
    fontSize: 16,
    color: "#E5E7EB",
    textAlign: "center",
    marginBottom: 24,
  },
  xp: {
    fontSize: 24,
    fontWeight: "bold",
    color: "#22C55E",
    marginBottom: 32,
  },
  botao: {
    backgroundColor: "#FFFFFF",
    paddingVertical: 14,
    paddingHorizontal: 32,
    borderRadius: 6,
  },
  botaoTexto: {
    color: "#0F172A",
    fontSize: 16,
    fontWeight: "bold",
  },
});
