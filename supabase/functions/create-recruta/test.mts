// test.mts — teste ISOLADO da correção A-10 em create-recruta.
//
// Mocka o cliente Supabase (interface SupabaseLike): NÃO cria usuário Auth, NÃO
// escreve em recrutas, NÃO chama nenhum banco. Prova apenas a propagação de id.
//
// Rodar (Node 22.6+ com type-stripping nativo; sem dependências):
//   node supabase/functions/create-recruta/test.mts
//
// Cobre a regressão do A-10: a RPC atribuir_missao_inicial deve receber o
// recrutas.id (retornado pelo INSERT), NUNCA o auth_id.

import assert from "node:assert/strict";
import { provisionRecruta, type SupabaseLike } from "./core.ts";

// IDs deliberadamente distintos para expor o bug se ele voltar.
const AUTH_ID = "11111111-1111-1111-1111-111111111111"; // auth.uid()
const RECRUTA_ID = "22222222-2222-2222-2222-222222222222"; // recrutas.id gerado no INSERT

function makeMockClient() {
  const calls: {
    createUserCalled: boolean;
    insertedRow?: Record<string, unknown>;
    rpcName?: string;
    rpcArgs?: Record<string, unknown>;
  } = { createUserCalled: false };

  const client: SupabaseLike = {
    auth: {
      admin: {
        async createUser() {
          calls.createUserCalled = true;
          return { data: { user: { id: AUTH_ID } }, error: null };
        },
      },
    },
    from(_table: string) {
      return {
        insert(row: Record<string, unknown>) {
          calls.insertedRow = row;
          return {
            select(_cols: string) {
              return {
                // INSERT retorna o id gerado pelo banco (recrutas.id), != auth_id.
                async single() {
                  return { data: { id: RECRUTA_ID }, error: null };
                },
              };
            },
          };
        },
      };
    },
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.rpcName = fn;
      calls.rpcArgs = args;
      return { error: null };
    },
  };

  return { client, calls };
}

let failed = 0;
function check(name: string, fn: () => void) {
  try {
    fn();
    console.log(`  ✔ ${name}`);
  } catch (e) {
    failed++;
    console.error(`  ✗ ${name}\n      ${(e as Error).message}`);
  }
}

const { client, calls } = makeMockClient();
const result = await provisionRecruta(client, {
  email: "teste-a10-fix@example.com",
  name: "Teste A10",
  senha: "SenhaTeste123!",
  forca: "marinha",
});

console.log("Teste isolado A-10 — create-recruta (cliente Supabase mockado, zero banco):");
check("provisionamento retorna ok", () => assert.equal(result.ok, true));
check("createUser foi chamado", () => assert.equal(calls.createUserCalled, true));
check("auth_id propagado corretamente", () =>
  assert.equal((result as { auth_id: string }).auth_id, AUTH_ID));
check("recruta_id capturado do INSERT (.select id)", () =>
  assert.equal((result as { recruta_id: string }).recruta_id, RECRUTA_ID));
check("INSERT em recrutas grava o auth_id correto", () =>
  assert.equal(calls.insertedRow?.auth_id, AUTH_ID));
check("A-10: RPC chamada é atribuir_missao_inicial", () =>
  assert.equal(calls.rpcName, "atribuir_missao_inicial"));
check("A-10 (correção): RPC recebe recrutas.id", () =>
  assert.equal(calls.rpcArgs?.p_recruta_id, RECRUTA_ID));
check("A-10 (regressão): RPC NUNCA recebe auth_id", () =>
  assert.notEqual(calls.rpcArgs?.p_recruta_id, AUTH_ID));
check("missão marcada como atribuída", () =>
  assert.equal((result as { missao_atribuida: boolean }).missao_atribuida, true));

if (failed > 0) {
  console.error(`\n❌ ${failed} asserção(ões) falharam.`);
  process.exit(1);
}
console.log("\n✅ Todas as asserções passaram — A-10 corrigido: RPC recebe recrutas.id, não auth_id.");
