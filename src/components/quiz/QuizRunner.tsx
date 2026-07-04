import React, { useMemo, useState } from 'react';
import { View, Text, StyleSheet, TouchableOpacity, ScrollView, ActivityIndicator, Alert } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { theme } from '../../theme';
import { QuizExecucao, QuizResposta, SubmitResult, submitAttempt } from '../../services/quizService';

// Componente reutilizável de execução de quiz OU simulado.
// Não bloqueia nada: é uma fonte adicional de XP. Avaliação/XP são server-side.
export function QuizRunner({ quiz, onDone }: { quiz: QuizExecucao; onDone?: () => void }) {
  const [answers, setAnswers] = useState<Record<string, string>>({}); // pergunta_id -> alternativa_id
  const [submitting, setSubmitting] = useState(false);
  const [result, setResult] = useState<SubmitResult | null>(null);

  const perguntas = quiz.perguntas ?? [];
  const allAnswered = useMemo(
    () => perguntas.length > 0 && perguntas.every((p) => answers[p.pergunta_id]),
    [perguntas, answers],
  );

  async function handleSubmit() {
    if (submitting || result) return;
    setSubmitting(true);
    try {
      const respostas: QuizResposta[] = perguntas
        .filter((p) => answers[p.pergunta_id])
        .map((p) => ({ pergunta_id: p.pergunta_id, alternativa_id: answers[p.pergunta_id] }));
      const r = await submitAttempt(quiz.id, respostas);
      if (!r.ok) {
        Alert.alert('Não foi possível enviar', r.reason ?? 'Tente novamente.');
        setSubmitting(false);
        return;
      }
      setResult(r);
    } catch {
      Alert.alert('Erro', 'Falha ao enviar. Tente novamente.');
    } finally {
      setSubmitting(false);
    }
  }

  // ── Resultado ──────────────────────────────────────────────────────────────
  if (result) {
    const xp = result.xp_concedido ?? 0;
    return (
      <View style={styles.resultWrap}>
        <Ionicons name="ribbon-outline" size={56} color={theme.colors.gold} />
        <Text style={styles.resultScore}>
          {result.total_acertos}/{result.total_perguntas} — {result.percentual}%
        </Text>
        <Text style={styles.resultXp}>
          {xp > 0
            ? `+${xp} XP`
            : result.primeira_tentativa
              ? 'Sem XP nesta faixa de acerto'
              : 'Sem XP (você já havia respondido)'}
        </Text>
        <TouchableOpacity style={styles.primaryBtn} onPress={onDone}>
          <Text style={styles.primaryBtnText}>CONCLUIR</Text>
        </TouchableOpacity>
      </View>
    );
  }

  // ── Execução ───────────────────────────────────────────────────────────────
  return (
    <View style={styles.flex}>
      <ScrollView contentContainerStyle={styles.list} showsVerticalScrollIndicator={false}>
        <Text style={styles.title}>{quiz.titulo}</Text>
        {perguntas.map((p, idx) => (
          <View key={p.pergunta_id} style={styles.card}>
            <Text style={styles.enunciado}>{idx + 1}. {p.enunciado}</Text>
            {(p.alternativas ?? []).map((a) => {
              const selected = answers[p.pergunta_id] === a.alternativa_id;
              return (
                <TouchableOpacity
                  key={a.alternativa_id}
                  style={[styles.alt, selected && styles.altSelected]}
                  onPress={() => setAnswers((prev) => ({ ...prev, [p.pergunta_id]: a.alternativa_id }))}
                  activeOpacity={0.8}
                >
                  <Ionicons
                    name={selected ? 'radio-button-on' : 'radio-button-off'}
                    size={18}
                    color={selected ? theme.colors.gold : theme.colors.textSecondary}
                    style={{ marginRight: 10 }}
                  />
                  <Text style={[styles.altText, selected && { color: theme.colors.textPrimary }]}>{a.texto}</Text>
                </TouchableOpacity>
              );
            })}
          </View>
        ))}
      </ScrollView>

      <View style={styles.footer}>
        <TouchableOpacity
          style={[styles.primaryBtn, (!allAnswered || submitting) && { opacity: 0.5 }]}
          onPress={handleSubmit}
          disabled={!allAnswered || submitting}
        >
          {submitting ? (
            <ActivityIndicator color="#000" />
          ) : (
            <Text style={styles.primaryBtnText}>{allAnswered ? 'ENVIAR RESPOSTAS' : 'RESPONDA TODAS'}</Text>
          )}
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  flex: { flex: 1 },
  list: { padding: 16, paddingBottom: 24, gap: 12 },
  title: { color: theme.colors.gold, fontSize: 16, fontWeight: '700', marginBottom: 4 },
  card: {
    backgroundColor: theme.colors.surface,
    borderRadius: 12,
    padding: 16,
    gap: 8,
  },
  enunciado: { color: theme.colors.textPrimary, fontSize: 15, fontWeight: '600', marginBottom: 6, lineHeight: 21 },
  alt: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: 10,
    paddingHorizontal: 12,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: '#2a2f36',
  },
  altSelected: { borderColor: theme.colors.gold, backgroundColor: 'rgba(212,175,55,0.08)' },
  altText: { color: theme.colors.textSecondary, fontSize: 14, flex: 1, lineHeight: 20 },
  footer: { padding: 16, borderTopWidth: 1, borderTopColor: '#333' },
  primaryBtn: {
    backgroundColor: theme.colors.gold,
    borderRadius: 12,
    paddingVertical: 15,
    alignItems: 'center',
    justifyContent: 'center',
  },
  primaryBtnText: { color: '#000', fontWeight: '800', letterSpacing: 0.5 },
  resultWrap: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 12, padding: 32 },
  resultScore: { color: theme.colors.textPrimary, fontSize: 26, fontWeight: '800' },
  resultXp: { color: theme.colors.gold, fontSize: 18, fontWeight: '700', marginBottom: 12 },
});
