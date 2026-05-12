/**
 * worker-os.ts — Vitrinni OS Task Worker
 *
 * Adapter determinístico entre a fila os_tasks (Supabase) e o executor HTTP local.
 * NÃO interpreta regras de negócio, XP, IEA, C9 ou acesso.
 * Responsabilidade única: fetch → execute → update status → log.
 *
 * Fase 2 do Vitrinni OS.
 */

import { createClient, SupabaseClient } from '@supabase/supabase-js';

// ── Validação de variáveis obrigatórias ───────────────────────────────────────
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL) {
  console.error('[WORKER-OS] FATAL: variável SUPABASE_URL não definida.');
  process.exit(1);
}
if (!SUPABASE_SERVICE_ROLE_KEY) {
  console.error('[WORKER-OS] FATAL: variável SUPABASE_SERVICE_ROLE_KEY não definida.');
  process.exit(1);
}

// ── Configuração com defaults ─────────────────────────────────────────────────
const OS_WORKER_ID = process.env.OS_WORKER_ID ?? 'worker-1';
const OS_WORKER_POLL_INTERVAL_MS = Math.max(
  500,
  parseInt(process.env.OS_WORKER_POLL_INTERVAL_MS ?? '2000', 10) || 2000,
);
const OS_EXECUTOR_URL = process.env.OS_EXECUTOR_URL ?? 'http://127.0.0.1:3099/execute';
const OS_EXECUTOR_TIMEOUT_MS = 30_000; // 30 segundos — não configurável externamente

// ── Supabase client (service_role — nunca expor esta chave) ───────────────────
const supabase: SupabaseClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// ── Tipos ─────────────────────────────────────────────────────────────────────

interface OsTask {
  id: string;
  task_type: string;
  payload: Record<string, unknown>;
  correlation_id: string;
  status: string;
  attempts: number;
  max_attempts: number;
  retry_after?: string | null;
  scheduled_for?: string | null;
  error_message?: string | null;
  result?: Record<string, unknown> | null;
  finished_at?: string | null;
  created_at: string;
}

type LogLevel = 'info' | 'warn' | 'error';

interface TaskLogEntry {
  task_id: string;
  correlation_id: string;
  level: LogLevel;
  event_type: string;
  message: string;
  metadata?: Record<string, unknown>;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Remove tokens JWT e segredos de strings de erro antes de persistir. */
function sanitizeError(raw: string): string {
  return raw
    .replace(/eyJ[A-Za-z0-9._-]{10,}/g, '[REDACTED_JWT]')
    .replace(/service_role[^"'\s]*/gi, '[REDACTED_ROLE]')
    .slice(0, 1000);
}

/** Registra evento em public.os_task_logs. Falha silenciosa (não aborta fluxo principal). */
async function writeLog(entry: TaskLogEntry): Promise<void> {
  const { error } = await supabase.from('os_task_logs').insert({
    task_id: entry.task_id,
    correlation_id: entry.correlation_id,
    level: entry.level,
    event_type: entry.event_type,
    message: entry.message,
    metadata: {
      worker_id: OS_WORKER_ID,
      ...(entry.metadata ?? {}),
    },
  });

  if (error) {
    // Não lançar — falha de log não deve derrubar o worker
    console.error('[WORKER-OS] Falha ao gravar log', {
      event_type: entry.event_type,
      task_id: entry.task_id,
      db_error: error.message,
    });
  }
}

/** Atualiza campos de uma task. Falha silenciosa com log de console. */
async function updateTask(taskId: string, patch: Record<string, unknown>): Promise<void> {
  const { error } = await supabase
    .from('os_tasks')
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq('id', taskId);

  if (error) {
    console.error('[WORKER-OS] Falha ao atualizar task', {
      task_id: taskId,
      patch_keys: Object.keys(patch),
      db_error: error.message,
    });
  }
}

// ── Executor HTTP local ───────────────────────────────────────────────────────

interface ExecutorPayload {
  task_id: string;
  task_type: string;
  payload: Record<string, unknown>;
  correlation_id: string;
}

interface ExecutorResponse {
  ok: boolean;
  result?: Record<string, unknown>;
  error?: string;
}

/**
 * Envia a task para o executor HTTP local (http://127.0.0.1:3099/execute).
 * Lança erro em caso de falha HTTP ou timeout.
 */
async function callExecutor(task: OsTask): Promise<ExecutorResponse> {
  const body: ExecutorPayload = {
    task_id: task.id,
    task_type: task.task_type,
    payload: task.payload,
    correlation_id: task.correlation_id,
  };

  let response: Response;
  try {
    response = await fetch(OS_EXECUTOR_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(OS_EXECUTOR_TIMEOUT_MS),
    });
  } catch (networkErr: unknown) {
    const msg = networkErr instanceof Error ? networkErr.message : String(networkErr);
    throw new Error(`executor_network_error: ${msg}`);
  }

  if (!response.ok) {
    const text = await response.text().catch(() => '(sem corpo)');
    throw new Error(`executor_http_${response.status}: ${text.slice(0, 300)}`);
  }

  let data: ExecutorResponse;
  try {
    data = (await response.json()) as ExecutorResponse;
  } catch {
    throw new Error('executor_invalid_json_response');
  }

  return data;
}

// ── Processamento de uma task ─────────────────────────────────────────────────

async function processTask(task: OsTask): Promise<void> {
  const { id, correlation_id, task_type, attempts, max_attempts } = task;

  console.log(`[WORKER-OS] task_received id=${id} type=${task_type} attempt=${attempts + 1}/${max_attempts}`);

  // Log: task_received
  await writeLog({
    task_id: id,
    correlation_id,
    level: 'info',
    event_type: 'task_received',
    message: `Task recebida: ${task_type} (tentativa ${attempts + 1}/${max_attempts})`,
    metadata: { task_type, attempt: attempts + 1, max_attempts },
  });

  let executorResponse: ExecutorResponse | null = null;
  let executorError: string | null = null;

  try {
    executorResponse = await callExecutor(task);

    // O executor pode retornar { ok: false } mesmo com HTTP 200
    if (executorResponse.ok === false) {
      const rawErr = executorResponse.error ?? 'executor_returned_ok_false';
      throw new Error(rawErr);
    }
  } catch (err: unknown) {
    const raw = err instanceof Error ? err.message : String(err);
    executorError = sanitizeError(raw);
    executorResponse = null;
  }

  const now = new Date().toISOString();

  if (executorResponse !== null) {
    // ── SUCESSO ───────────────────────────────────────────────────────────────
    await updateTask(id, {
      status: 'completed',
      result: executorResponse.result ?? null,
      finished_at: now,
      error_message: null,
    });

    await writeLog({
      task_id: id,
      correlation_id,
      level: 'info',
      event_type: 'task_completed',
      message: `Task concluída com sucesso: ${task_type}`,
      metadata: { task_type },
    });

    console.log(`[WORKER-OS] task_completed id=${id} type=${task_type}`);
  } else {
    // ── FALHA ─────────────────────────────────────────────────────────────────
    const newAttempts = attempts + 1;

    if (newAttempts < max_attempts) {
      // Ainda há tentativas — backoff exponencial (30s × attempt, máximo 5min)
      const delayMs = Math.min(30_000 * newAttempts, 300_000);
      const retryAfter = new Date(Date.now() + delayMs).toISOString();

      await updateTask(id, {
        status: 'pending',
        attempts: newAttempts,
        retry_after: retryAfter,
        error_message: executorError,
      });

      await writeLog({
        task_id: id,
        correlation_id,
        level: 'warn',
        event_type: 'task_retry_scheduled',
        message: `Retry agendado (${newAttempts}/${max_attempts}): ${executorError}`,
        metadata: {
          task_type,
          attempts: newAttempts,
          max_attempts,
          retry_after: retryAfter,
          error: executorError,
        },
      });

      console.warn(
        `[WORKER-OS] task_retry_scheduled id=${id} attempt=${newAttempts}/${max_attempts} retry_after=${retryAfter}`,
      );
    } else {
      // Esgotou tentativas → failed definitivo
      await updateTask(id, {
        status: 'failed',
        attempts: newAttempts,
        error_message: executorError,
        finished_at: now,
      });

      await writeLog({
        task_id: id,
        correlation_id,
        level: 'error',
        event_type: 'task_failed',
        message: `Task falhou definitivamente após ${newAttempts} tentativas: ${executorError}`,
        metadata: {
          task_type,
          attempts: newAttempts,
          max_attempts,
          error: executorError,
        },
      });

      console.error(`[WORKER-OS] task_failed id=${id} type=${task_type} attempts=${newAttempts}`);
    }
  }
}

// ── Ciclo de poll ─────────────────────────────────────────────────────────────

async function poll(): Promise<void> {
  // Chama a RPC que retorna (e bloqueia) a próxima task disponível
  const { data, error } = await supabase.rpc('os_fetch_next_task');

  if (error) {
    console.error('[WORKER-OS] Erro na RPC os_fetch_next_task:', error.message);
    return;
  }

  // Sem tasks disponíveis — aguarda próximo ciclo silenciosamente
  if (!data || (Array.isArray(data) && data.length === 0)) {
    return;
  }

  // A RPC pode retornar objeto único ou array com um elemento
  const raw = Array.isArray(data) ? data[0] : data;
  const task = raw as OsTask;

  // Guarda de segurança: recusa tasks malformadas
  if (!task.id || !task.task_type || task.payload === undefined || task.payload === null) {
    console.error('[WORKER-OS] Task malformada recebida — ignorando', {
      has_id: !!task.id,
      has_task_type: !!task.task_type,
      has_payload: task.payload !== undefined,
    });
    return;
  }

  await processTask(task);
}

// ── Entrypoint principal ──────────────────────────────────────────────────────

async function main(): Promise<void> {
  // Log de boot — nunca imprime SUPABASE_SERVICE_ROLE_KEY
  console.log('[WORKER-OS] Iniciando', {
    worker_id: OS_WORKER_ID,
    poll_interval_ms: OS_WORKER_POLL_INTERVAL_MS,
    executor_url: OS_EXECUTOR_URL,
    supabase_url: SUPABASE_URL,
  });

  // Shutdown gracioso: aguarda poll atual terminar antes de sair
  let running = true;

  const shutdown = (signal: string) => {
    console.log(`[WORKER-OS] ${signal} recebido — aguardando ciclo atual e encerrando...`);
    running = false;
  };

  process.on('SIGINT', () => shutdown('SIGINT'));
  process.on('SIGTERM', () => shutdown('SIGTERM'));

  // Loop principal
  while (running) {
    try {
      await poll();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      console.error('[WORKER-OS] Erro não tratado no ciclo de poll:', msg);
      // Não sai do loop — resiliência a falhas transitórias
    }

    if (running) {
      await new Promise<void>((resolve) => setTimeout(resolve, OS_WORKER_POLL_INTERVAL_MS));
    }
  }

  console.log('[WORKER-OS] Worker encerrado.');
}

main().catch((err: unknown) => {
  const msg = err instanceof Error ? err.message : String(err);
  console.error('[WORKER-OS] Erro fatal na inicialização:', msg);
  process.exit(1);
});
