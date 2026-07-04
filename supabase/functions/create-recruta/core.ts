// core.ts — lógica pura de provisionamento de recruta, testável em isolamento.
//
// SEM imports Deno / SEM createClient concreto: recebe um cliente Supabase por
// injeção de dependência (interface estrutural SupabaseLike). Isso permite testar
// a lógica com um mock, sem tocar em nenhum banco.
//
// CORREÇÃO A-10 (2026-07-04):
//   Antes, a função passava `data.user.id` (o AUTH_ID) para a RPC
//   `atribuir_missao_inicial`, que espera o `recrutas.id`. Como recrutas.id ≠ auth_id,
//   a atribuição de missão falhava silenciosamente.
//   Agora o INSERT em `recrutas` retorna o `id` gerado (.select("id").single()) e é
//   ESSE id que vai para a RPC. Ver test.mts para a validação.

export interface RecrutaInput {
  email?: string;
  name?: string;
  senha?: string;
  forca?: string;
}

// Interface estrutural mínima do cliente Supabase usada aqui (facilita o mock no teste).
export interface SupabaseLike {
  auth: {
    admin: {
      createUser(args: {
        email: string;
        password: string;
        email_confirm: boolean;
      }): Promise<{ data: { user: { id: string } | null }; error: { message: string } | null }>;
    };
  };
  from(table: string): {
    insert(row: Record<string, unknown>): {
      select(cols: string): {
        single(): Promise<{ data: { id: string } | null; error: { message: string } | null }>;
      };
    };
  };
  rpc(fn: string, args: Record<string, unknown>): Promise<{ error: { message: string } | null }>;
}

export type ProvisionResult =
  | { ok: true; auth_id: string; recruta_id: string; missao_atribuida: boolean }
  | { ok: false; status: number; error: string };

export async function provisionRecruta(
  client: SupabaseLike,
  input: RecrutaInput,
): Promise<ProvisionResult> {
  const { email, name, senha, forca = "marinha" } = input;

  if (!email || !senha) {
    return { ok: false, status: 400, error: "Email e senha são obrigatórios" };
  }

  // 1. Criar usuário Auth (admin — senha definida pelo chamador).
  const { data, error } = await client.auth.admin.createUser({
    email,
    password: senha,
    email_confirm: true,
  });
  if (error || !data.user) {
    return { ok: false, status: 400, error: error?.message ?? "auth_create_failed" };
  }
  const authId = data.user.id;

  // 2. Inserir em recrutas E CAPTURAR o recrutas.id gerado (correção A-10).
  const { data: recrutaRow, error: dbError } = await client
    .from("recrutas")
    .insert({
      auth_id: authId,
      email,
      nome: name,
      forca,
      patente: "Recruta",
      plano: "basico",
      status: "ativo",
    })
    .select("id")
    .single();

  if (dbError || !recrutaRow) {
    return { ok: false, status: 400, error: dbError?.message ?? "recruta_insert_failed" };
  }
  const recrutaId = recrutaRow.id;

  // 3. Atribuir missão inicial usando recrutas.id (NÃO auth_id) — correção A-10.
  //    Mantém o comportamento original: erro na missão não é fatal (só sinalizado).
  const { error: missaoError } = await client.rpc("atribuir_missao_inicial", {
    p_recruta_id: recrutaId,
  });

  return {
    ok: true,
    auth_id: authId,
    recruta_id: recrutaId,
    missao_atribuida: !missaoError,
  };
}
