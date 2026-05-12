// RCC-0.5 — Mapeador de Erros Institucional
// Nenhum erro técnico deve chegar ao usuário.
// Todo erro passa por aqui antes de ser renderizado.

export type MappedError = {
  title: string;
  message: string;
  canRetry: boolean;
};

// Prefixos/substrings técnicas que nunca devem aparecer na UI
const TECHNICAL_PATTERNS = [
  /^(PGRST|42\d{3}|23\d{3}|auth\/)/i,
  /unexpected token/i,
  /fetch failed/i,
  /network request failed/i,
  /aborted/i,
  /timeout/i,
  /json parse/i,
  /undefined is not/i,
  /cannot read prop/i,
  /invalid uuid/i,
  /foreign key/i,
  /duplicate key/i,
  /row-level security/i,
];

function isTechnical(msg: string): boolean {
  return TECHNICAL_PATTERNS.some((p) => p.test(msg));
}

// ── Mapeamentos por código ────────────────────────────────────────────────────

const SUPABASE_CODES: Record<string, MappedError> = {
  // Auth
  'invalid_credentials':       { title: 'Acesso negado', message: 'Identificação ou senha incorretos.', canRetry: true },
  'email_not_confirmed':        { title: 'Acesso pendente', message: 'Confirme seu cadastro pelo e-mail institucional.', canRetry: false },
  'user_not_found':             { title: 'Identidade não encontrada', message: 'Nenhum registro com estas credenciais.', canRetry: true },
  'weak_password':              { title: 'Senha insuficiente', message: 'Utilize uma senha mais robusta.', canRetry: true },
  'over_request_rate_limit':    { title: 'Limite de acesso atingido', message: 'Aguarde alguns instantes antes de tentar novamente.', canRetry: false },
  'session_not_found':          { title: 'Sessão encerrada', message: 'Faça login novamente para continuar.', canRetry: false },

  // PostgREST / Supabase DB
  'PGRST116':  { title: 'Registro não encontrado', message: 'As informações solicitadas não estão disponíveis.', canRetry: false },
  'PGRST301':  { title: 'Sem autorização', message: 'Você não tem permissão para esta operação.', canRetry: false },
  '23505':     { title: 'Registro duplicado', message: 'Esta operação já foi realizada anteriormente.', canRetry: false },
  '23503':     { title: 'Referência inválida', message: 'Os dados enviados contêm uma referência inválida.', canRetry: false },
  '42501':     { title: 'Sem autorização', message: 'Acesso negado pelo sistema institucional.', canRetry: false },
};

const CHAT_CODES: Record<string, MappedError> = {
  timeout:    { title: 'QG sem resposta', message: 'O canal não respondeu a tempo. Tente novamente.', canRetry: true },
  offline:    { title: 'Sem conexão', message: 'Verifique sua rede e tente novamente.', canRetry: true },
  auth:       { title: 'Sessão inválida', message: 'Faça login novamente para continuar.', canRetry: false },
  server:     { title: 'Falha no QG', message: 'Ocorreu uma falha no servidor. Tente novamente em instantes.', canRetry: true },
  validation: { title: 'Envio inválido', message: 'Verifique o conteúdo e tente novamente.', canRetry: false },
};

// ── Função principal ──────────────────────────────────────────────────────────

export function mapError(err: unknown): MappedError {
  if (!err) {
    return { title: 'Ocorreu um erro', message: 'Tente novamente em instantes.', canRetry: true };
  }

  // ChatError tipado
  if (typeof err === 'object' && err !== null && 'name' in err && (err as any).name === 'ChatError') {
    const code = (err as any).code as string;
    return CHAT_CODES[code] ?? { title: 'Falha na comunicação', message: 'Tente novamente em instantes.', canRetry: true };
  }

  const e = err as any;

  // Supabase error com código explícito
  if (e.code && SUPABASE_CODES[e.code]) {
    return SUPABASE_CODES[e.code];
  }

  // Supabase error por message
  if (e.message) {
    const msg: string = e.message;

    if (msg.includes('Invalid login credentials') || msg.includes('invalid_credentials')) {
      return SUPABASE_CODES['invalid_credentials'];
    }
    if (msg.includes('Email not confirmed') || msg.includes('email_not_confirmed')) {
      return SUPABASE_CODES['email_not_confirmed'];
    }
    if (msg.toLowerCase().includes('network') || msg.toLowerCase().includes('fetch')) {
      return { title: 'Sem conexão', message: 'Verifique sua rede e tente novamente.', canRetry: true };
    }
    if (msg.toLowerCase().includes('timeout')) {
      return { title: 'Tempo esgotado', message: 'A operação demorou demais. Tente novamente.', canRetry: true };
    }

    // Se não for texto técnico, usar como está
    if (!isTechnical(msg) && msg.length < 120) {
      return { title: 'Ocorreu um problema', message: msg, canRetry: true };
    }
  }

  // Fallback seguro
  return { title: 'Ocorreu um problema', message: 'Tente novamente em instantes. Se persistir, contate o suporte.', canRetry: true };
}

// ── Utilitário para renderizar erros inline ───────────────────────────────────
export function errorToString(err: unknown): string {
  return mapError(err).message;
}
