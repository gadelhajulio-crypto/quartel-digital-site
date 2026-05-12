// RCC-0.5 — Normalizador de Eventos Institucionais
// Nenhum identificador técnico deve chegar à interface do usuário.

// ── Mapeamento de tipos de evento ─────────────────────────────────────────────

const EVENT_TYPE_LABELS: Record<string, string> = {
  lesson:      'AULA',
  review:      'REVISÃO',
  xp:          'PONTUAÇÃO',
  medal:       'MEDALHA',
  system:      'SISTEMA',
  module:      'MÓDULO',
  ranking:     'RANKING',
  login:       'ACESSO',
  onboarding:  'CADASTRO',
  progress:    'PROGRESSO',
  achievement: 'CONQUISTA',
};

export function mapEventType(slug: string): string {
  if (!slug) return 'EVENTO';
  return EVENT_TYPE_LABELS[slug.toLowerCase()] ?? slug.replace(/_/g, ' ').toUpperCase();
}

// ── Sanitização de texto livre ────────────────────────────────────────────────

// UUID v4
const UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;

// Padrões inequivocamente técnicos
const TECHNICAL_RE = [
  /^(PGRST\d+|pg_|auth\/)/i,
  /^\d{5}$/,       // códigos de erro postgres
  /^(null|undefined|NaN)$/i,
  /^v_\w+$/i,      // nomes de view
  /^rpc_\w+$/i,    // nomes de RPC
];

function looksLikeTechnical(text: string): boolean {
  const t = text.trim();
  return TECHNICAL_RE.some((re) => re.test(t));
}

export function sanitizeText(text: string): string {
  if (!text) return '';
  return text.replace(UUID_RE, '—').trim();
}

export function sanitizeTitle(title: string, fallback = 'Registro institucional'): string {
  if (!title) return fallback;
  const cleaned = sanitizeText(title);
  if (!cleaned || cleaned.length < 2 || looksLikeTechnical(cleaned)) return fallback;
  return cleaned;
}

export function sanitizeDescription(desc: string): string {
  if (!desc) return '';
  const cleaned = sanitizeText(desc);
  if (looksLikeTechnical(cleaned)) return '';
  return cleaned;
}
