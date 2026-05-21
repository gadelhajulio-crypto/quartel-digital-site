// Wave 5a-3 — Registro de push token institucional.
//
// INVARIANTES:
//   - nunca roda em simulador/emulador (Device.isDevice = false)
//   - nunca roda sem auth confirmada (guarda pelo parâmetro `enabled`)
//   - nunca loga o token completo — apenas plataforma e códigos de erro
//   - nunca bloqueia UX — fire-and-forget silencioso
//   - idempotente — RPC usa UPSERT; guard de sessão evita chamadas duplicadas
//   - platform restrita a 'ios' | 'android' (contrato da RPC)

import { useEffect, useRef } from 'react';
import { Platform } from 'react-native';
import * as Device from 'expo-device';
import * as Notifications from 'expo-notifications';
import Constants from 'expo-constants';
import { supabase } from '../lib/supabase';
import { logChatEvent } from '../utils/chatTelemetry';

// Guard de módulo: evita registro duplicado na mesma sessão de app
// (BootstrapGate pode re-renderizar várias vezes com enabled=true)
let _registeredThisSession = false;

/**
 * Solicita permissão de push e registra o Expo Push Token via
 * rpc_register_push_token quando `enabled` for true.
 *
 * @param enabled - true apenas quando recruta está autenticado,
 *                  onboarding concluído e billing OK.
 */
export function usePushToken(enabled: boolean): void {
  const hasAttempted = useRef(false);

  useEffect(() => {
    if (!enabled) return;
    if (hasAttempted.current) return;
    if (_registeredThisSession) return;

    hasAttempted.current = true;
    registerPushToken();
  }, [enabled]);
}

async function registerPushToken(): Promise<void> {
  // 1. Apenas devices físicos — simuladores/emuladores não suportam APNs/FCM
  if (!Device.isDevice) {
    logChatEvent('push_skipped_not_device', {});
    return;
  }

  // 2. Verificar permissão atual; solicitar se necessário
  const { status: existingStatus } = await Notifications.getPermissionsAsync();
  let finalStatus = existingStatus;

  if (existingStatus !== 'granted') {
    const { status } = await Notifications.requestPermissionsAsync();
    finalStatus = status;
  }

  logChatEvent('push_permission_checked', { status: finalStatus });

  if (finalStatus !== 'granted') {
    logChatEvent('push_permission_denied', {});
    return;
  }

  // 3. Obter Expo Push Token (requer projectId do EAS)
  const projectId = Constants.expoConfig?.extra?.eas?.projectId as string | undefined;
  if (!projectId) {
    logChatEvent('push_token_register_failed', { error_code: 'missing_project_id' });
    return;
  }

  let token: string;
  try {
    const result = await Notifications.getExpoPushTokenAsync({ projectId });
    token = result.data;
  } catch {
    logChatEvent('push_token_register_failed', { error_code: 'token_fetch_failed' });
    return;
  }

  if (!token) {
    logChatEvent('push_token_register_failed', { error_code: 'empty_token' });
    return;
  }

  // 4. Registrar via RPC — token nunca logado
  const platform: 'ios' | 'android' = Platform.OS === 'ios' ? 'ios' : 'android';

  const { error } = await supabase.rpc('rpc_register_push_token', {
    p_token: token,
    p_platform: platform,
  });

  if (error) {
    logChatEvent('push_token_register_failed', {
      error_code: error.code ?? 'rpc_error',
      status: error.message?.slice(0, 40),
    });
    return;
  }

  _registeredThisSession = true;
  logChatEvent('push_token_registered', { status: platform });
}
