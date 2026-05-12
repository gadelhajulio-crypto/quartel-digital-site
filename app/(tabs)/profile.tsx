import { View, Text, StyleSheet, TouchableOpacity, ActivityIndicator, Image } from 'react-native';
import { useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { useAuth } from '../../src/context/AuthContext';
import { useInstructors } from '../../src/hooks/useInstructors';
import { HierarchyBadge } from '../../src/components/HierarchyBadge';
import { InstitutionalLoading } from '../../src/components/InstitutionalLoading';
import { getCurrentIEA, checkIEAAuditAvailability, IEAData } from '../../src/services/ieaService';
import { getEliteStatus, EliteStatus, getCycleClassification, CycleClassification } from '../../src/services/eliteService';
import { DossierScreen } from '../../src/design/layout/DossierScreen';
import { InstitutionalCard } from '../../src/design/components/InstitutionalCard';
import { InstitutionalBadge } from '../../src/design/components/InstitutionalBadge';
import { InstitutionalButton } from '../../src/design/components/InstitutionalButton';
import { InstitutionalSection } from '../../src/design/components/InstitutionalSection';
import { dossie } from '../../src/design/themes/dossie';
import { typographyPresets } from '../../src/design/tokens/typography';

const FORCA_LABELS: Record<string, string> = {
  marinha: 'Marinha do Brasil',
  exercito: 'Exército Brasileiro',
  aeronautica: 'Força Aérea Brasileira',
};

export default function PerfilScreen() {
  const { profile, signOut, loading } = useAuth();
  const router = useRouter();
  const { instructors } = useInstructors();
  const [iea, setIea] = useState<IEAData | null>(null);
  const [loadingIea, setLoadingIea] = useState(true);
  const [hasAudit, setHasAudit] = useState(false);
  const [eliteStatus, setEliteStatus] = useState<EliteStatus | null>(null);
  const [cycleClass, setCycleClass] = useState<CycleClassification | null>(null);

  useEffect(() => {
    if (profile?.id) {
      loadIEA();
    }
  }, [profile?.id]);

  async function loadIEA() {
    try {
      if (profile?.id) {
        const data = await getCurrentIEA(profile.id);
        setIea(data);

        const auditAvailable = await checkIEAAuditAvailability();
        setHasAudit(auditAvailable);

        const elite = await getEliteStatus(profile.id);
        setEliteStatus(elite);

        const lastCycle = await getCycleClassification(profile.id);
        setCycleClass(lastCycle);
      }
    } catch (e) {
      console.warn('[Perfil] Dados institucionais temporariamente indisponíveis.');
    } finally {
      setLoadingIea(false);
    }
  }

  if (loading) {
    return <InstitutionalLoading />;
  }

  if (!profile) {
    return (
      <DossierScreen>
        <View style={styles.fallbackCenter}>
          <Text style={[typographyPresets.body, { color: dossie.colors.textSecondary, marginBottom: 20 }]}>
            Não foi possível carregar as informações institucionais.
          </Text>
          <InstitutionalButton
            theme={dossie}
            label="Sair do aplicativo"
            variant="ghost"
            onPress={async () => {
              try {
                await signOut();
              } finally {
                router.replace('/(auth)/login');
              }
            }}
          />
        </View>
      </DossierScreen>
    );
  }

  // Instrutor atual (v_instrutores_app via useInstructors)
  const currentInstructor =
    instructors.find((i) => i.codigo === profile?.instructor_profile_id) ?? null;

  // Prioridade de nome: nome_guerra → nome_operacional → nome_completo → nome → 'Recruta'
  const displayName =
    profile.nome_guerra ||
    (profile as any).nome_operacional ||
    (profile as any).nome_completo ||
    profile.nome ||
    'Recruta';

  const getIeaBadgeVariant = (concept: string): 'success' | 'accent' | 'muted' => {
    if (!concept) return 'muted';
    const n = concept.toLowerCase();
    if (n.includes('excelência') || n.includes('excelencia')) return 'success';
    if (n.includes('alta performance')) return 'accent';
    return 'muted';
  };

  return (
    <DossierScreen scrollable contentStyle={styles.content}>
      {/* ── CABEÇALHO ── */}
      <View style={styles.header}>
        <View style={styles.confidentialStamp}>
          <Text style={styles.confidentialText}>CONFIDENCIAL</Text>
        </View>
        <InstitutionalBadge theme={dossie} label="Ficha institucional" variant="accent" />
        <Text style={[typographyPresets.displayTitle, styles.displayName, { color: dossie.colors.accent }]}>
          {displayName}
        </Text>
        {profile.patente && (
          <Text style={[typographyPresets.label, { color: dossie.colors.muted }]}>
            {profile.patente}
          </Text>
        )}
      </View>

      {/* ── DADOS FUNCIONAIS ── */}
      <InstitutionalSection title="Dados funcionais" theme={dossie}>
        <InstitutionalCard theme={dossie} elevated>
          <DataRow label="Identificação" value={displayName} theme={dossie} />
          <Divider theme={dossie} />
          <DataRow label="Nome de guerra" value={displayName} theme={dossie} highlight />
        </InstitutionalCard>
      </InstitutionalSection>

      {/* ── VÍNCULO INSTITUCIONAL ── */}
      <InstitutionalSection title="Vínculo institucional" theme={dossie}>
        <InstitutionalCard theme={dossie} elevated>
          <DataRow
            label="Força"
            value={FORCA_LABELS[profile.forca] ?? profile.forca?.toUpperCase() ?? '—'}
            theme={dossie}
          />
          {profile.nivel_atual && (
            <>
              <Divider theme={dossie} />
              <View style={styles.hierRow}>
                <Text style={[typographyPresets.label, { color: dossie.colors.muted }]}>
                  Hierarquia
                </Text>
                <View style={styles.hierBadgeRow}>
                  {eliteStatus?.elegivel && (
                    <InstitutionalBadge
                      theme={dossie}
                      label="Elegível Elite"
                      variant="success"
                      style={{ marginRight: 8 }}
                    />
                  )}
                  <HierarchyBadge nivelAtual={profile.nivel_atual} />
                </View>
              </View>
            </>
          )}

          {/* Aviso regularidade */}
          {eliteStatus && !eliteStatus.elegivel && eliteStatus.regularidade < 70 && (
            <View
              style={[
                styles.regularidadeAlert,
                {
                  backgroundColor: dossie.colors.accentSoft,
                  borderColor: dossie.colors.accent,
                },
              ]}
            >
              <Text style={[typographyPresets.bodySmall, { color: dossie.colors.accent }]}>
                Elite indisponível neste ciclo · Regularidade: {eliteStatus.regularidade}%
              </Text>
            </View>
          )}

          {/* Classificação ciclo anterior */}
          {cycleClass && (
            <>
              <Divider theme={dossie} />
              <DataRow
                label="Último ciclo"
                value={`${cycleClass.hierarquia_atual} · ${cycleClass.score_final} pts`}
                theme={dossie}
              />
            </>
          )}
        </InstitutionalCard>
      </InstitutionalSection>

      {/* ── ÍNDICE DE DESEMPENHO ── */}
      <InstitutionalSection title="Índice de desempenho" theme={dossie}>
        <InstitutionalCard theme={dossie} elevated>
          <Text style={[typographyPresets.label, { color: dossie.colors.muted, marginBottom: 10 }]}>
            IEA — Índice de Excelência Acadêmica
          </Text>

          {loadingIea ? (
            <ActivityIndicator color={dossie.colors.accent} size="small" style={{ alignSelf: 'flex-start' }} />
          ) : iea ? (
            <View>
              <View style={styles.ieaScoreRow}>
                <Text style={[styles.ieaScore, { color: dossie.colors.text }]}>
                  {Math.round(iea.score)}
                </Text>
                <InstitutionalBadge
                  theme={dossie}
                  label={iea.concept}
                  variant={getIeaBadgeVariant(iea.concept)}
                />
              </View>
              <Text style={[typographyPresets.bodySmall, { color: dossie.colors.muted, marginTop: 8 }]}>
                Referência: {new Date(iea.updated_at).toLocaleDateString('pt-BR')}
              </Text>
              {hasAudit && (
                <TouchableOpacity
                  style={[
                    styles.auditBtn,
                    {
                      borderColor: dossie.colors.border,
                      backgroundColor: dossie.colors.surface,
                    },
                  ]}
                  onPress={() => {
                    alert('Detalhes do IEA em implementação via v_iea_audit');
                  }}
                >
                  <Text style={[typographyPresets.label, { color: dossie.colors.textSecondary }]}>
                    Ver detalhes do IEA
                  </Text>
                </TouchableOpacity>
              )}
            </View>
          ) : (
            <Text style={[typographyPresets.body, { color: dossie.colors.muted, fontStyle: 'italic' }]}>
              IEA em apuração
            </Text>
          )}
        </InstitutionalCard>
      </InstitutionalSection>

      {/* ── CONTATO INSTITUCIONAL ── */}
      <InstitutionalSection title="Contato institucional" theme={dossie}>
        <InstitutionalCard theme={dossie}>
          <DataRow
            label="Condecorações"
            value="Disponíveis na seção de medalhas"
            theme={dossie}
          />
        </InstitutionalCard>
      </InstitutionalSection>

      {/* ── MEU INSTRUTOR ── */}
      <InstitutionalSection title="Meu Instrutor" theme={dossie}>
        <InstitutionalCard theme={dossie} elevated>
          {currentInstructor ? (
            <View style={styles.instructorRow}>
              {currentInstructor.avatar_url ? (
                <Image
                  source={{ uri: currentInstructor.avatar_url }}
                  style={styles.instructorAvatar}
                  resizeMode="cover"
                />
              ) : (
                <View
                  style={[styles.instructorAvatar, { backgroundColor: dossie.colors.surface }]}
                />
              )}
              <View style={styles.instructorInfo}>
                <Text style={[typographyPresets.label, { color: dossie.colors.muted }]}>
                  {currentInstructor.titulo}
                </Text>
                <Text
                  style={[
                    typographyPresets.cardTitle,
                    { color: dossie.colors.text, marginTop: 2 },
                  ]}
                >
                  {currentInstructor.nome}
                </Text>
              </View>
            </View>
          ) : (
            <Text
              style={[
                typographyPresets.body,
                { color: dossie.colors.muted, fontStyle: 'italic' },
              ]}
            >
              Nenhum instrutor selecionado.
            </Text>
          )}

          <View style={[styles.instructorDivider, { backgroundColor: dossie.colors.border }]} />

          <TouchableOpacity
            style={[styles.instructorBtn, { borderColor: dossie.colors.border }]}
            onPress={() => router.push('/(stack)/instructor/select' as any)}
            activeOpacity={0.75}
          >
            <Text style={[typographyPresets.label, { color: dossie.colors.accent }]}>
              Trocar Instrutor
            </Text>
          </TouchableOpacity>
        </InstitutionalCard>
      </InstitutionalSection>

      {/* ── LINKS ── */}
      <View style={styles.links}>
        <LinkRow
          label="Histórico completo"
          onPress={() => router.push('/(tabs)/history')}
          theme={dossie}
        />
        <LinkRow
          label="Configurações"
          onPress={() => router.push('/(tabs)/settings')}
          theme={dossie}
        />
      </View>

      {/* ── SAIR ── */}
      <TouchableOpacity
        style={styles.signOut}
        onPress={async () => {
          try {
            await signOut();
          } finally {
            router.replace('/(auth)/login');
          }
        }}
      >
        <Text style={[typographyPresets.label, { color: dossie.colors.muted }]}>
          Encerrar sessão
        </Text>
      </TouchableOpacity>

      <View style={{ height: 100 }} />
    </DossierScreen>
  );
}

// ── helpers visuais internos ─────────────────────────────────────────────────

function DataRow({
  label,
  value,
  theme: t,
  highlight = false,
}: {
  label: string;
  value: string;
  theme: typeof dossie;
  highlight?: boolean;
}) {
  return (
    <View style={dataRowStyles.row}>
      <Text style={[typographyPresets.label, { color: t.colors.muted, flex: 1 }]}>
        {label}
      </Text>
      <Text
        style={[
          typographyPresets.cardTitle,
          {
            color: highlight ? t.colors.accent : t.colors.text,
            letterSpacing: highlight ? 1.5 : 0,
            textAlign: 'right',
            flex: 2,
          },
        ]}
        numberOfLines={2}
      >
        {value}
      </Text>
    </View>
  );
}

function Divider({ theme: t }: { theme: typeof dossie }) {
  return (
    <View style={[dataRowStyles.divider, { backgroundColor: t.colors.border }]} />
  );
}

function LinkRow({
  label,
  onPress,
  theme: t,
}: {
  label: string;
  onPress: () => void;
  theme: typeof dossie;
}) {
  return (
    <TouchableOpacity
      style={[dataRowStyles.linkRow, { borderTopColor: t.colors.border }]}
      onPress={onPress}
      activeOpacity={0.7}
    >
      <Text style={[typographyPresets.cardTitle, { color: t.colors.text }]}>{label}</Text>
      <Text style={{ color: t.colors.muted, fontSize: 18 }}>›</Text>
    </TouchableOpacity>
  );
}

const dataRowStyles = StyleSheet.create({
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    paddingVertical: 10,
  },
  divider: {
    height: 1,
  },
  linkRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 18,
    borderTopWidth: 1,
  },
});

const styles = StyleSheet.create({
  fallbackCenter: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  content: {
    paddingTop: 56,
    paddingBottom: 24,
  },
  header: {
    marginBottom: 32,
    gap: 6,
  },
  confidentialStamp: {
    alignSelf: 'flex-start',
    borderWidth: 1.5,
    borderColor: '#7a1a1a',
    borderRadius: 2,
    paddingHorizontal: 10,
    paddingVertical: 3,
    marginBottom: 8,
    transform: [{ rotate: '-4deg' }],
  },
  confidentialText: {
    color: '#7a1a1a',
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 3,
  },
  displayName: {
    fontSize: 30,
    marginTop: 6,
  },
  hierRow: {
    paddingVertical: 10,
  },
  hierBadgeRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 8,
    flexWrap: 'wrap',
    gap: 8,
  },
  regularidadeAlert: {
    marginTop: 12,
    padding: 10,
    borderRadius: 6,
    borderWidth: 1,
  },
  ieaScoreRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  ieaScore: {
    fontSize: 36,
    fontWeight: '700',
  },
  auditBtn: {
    marginTop: 12,
    paddingVertical: 8,
    paddingHorizontal: 12,
    borderWidth: 1,
    borderRadius: 6,
    alignItems: 'center',
  },
  links: {
    marginTop: 8,
  },
  signOut: {
    marginTop: 32,
    marginBottom: 8,
    alignItems: 'center',
    paddingVertical: 16,
  },
  instructorRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    paddingVertical: 4,
  },
  instructorAvatar: {
    width: 48,
    height: 48,
    borderRadius: 24,
  },
  instructorInfo: {
    flex: 1,
  },
  instructorDivider: {
    height: 1,
    marginVertical: 12,
  },
  instructorBtn: {
    paddingVertical: 10,
    borderWidth: 1,
    borderRadius: 6,
    alignItems: 'center',
  },
});
