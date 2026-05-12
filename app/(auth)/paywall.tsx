import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Linking,
  ScrollView,
  StyleSheet,
  Text,
  TouchableOpacity,
  View,
} from 'react-native';
import { useAuth } from '../../src/context/AuthContext';
import { useBootstrapGate } from '../../src/context/BootstrapGateContext';
import { getBillingStatus, BillingStatus } from '../../src/services/billingService';
import { createCheckoutSession, PlanSlug } from '../../src/services/stripeService';

const PLANS: { slug: PlanSlug; label: string; description: string }[] = [
  
  { slug: 'anual', label: 'Plano Anual', description: '12 meses de acesso.' },
];

export default function Paywall() {
  const { profile, signOut } = useAuth();
  const { retriggerGate } = useBootstrapGate();

  const [billing, setBilling] = useState<BillingStatus | null>(null);
  const [loadingBilling, setLoadingBilling] = useState(true);
  const [billingError, setBillingError] = useState<string | null>(null);

  const [checkoutLoading, setCheckoutLoading] = useState(false);
  const [checkoutError, setCheckoutError] = useState<string | null>(null);

  // Carrega billing ao montar
  useEffect(() => {
    async function load() {
      try {
        const data = await getBillingStatus();
        setBilling(data);
      } catch {
        setBillingError('Não foi possível carregar as informações de acesso.');
      } finally {
        setLoadingBilling(false);
      }
    }
    load();
  }, []);

  // Escuta deep link de retorno do checkout (quarteldigital://checkout/success)
  useEffect(() => {
    function handleUrl({ url }: { url: string }) {
      if (url.includes('checkout/success')) {
        retriggerGate();
      }
    }

    const subscription = Linking.addEventListener('url', handleUrl);

    // Caso o app tenha sido aberto a partir do background pelo deep link
    Linking.getInitialURL().then((url) => {
      if (url && url.includes('checkout/success')) {
        retriggerGate();
      }
    });

    return () => subscription.remove();
  }, [retriggerGate]);

  async function iniciarCheckout(plan_slug: PlanSlug) {
    if (!profile) return;

    setCheckoutLoading(true);
    setCheckoutError(null);

    try {
      const result = await createCheckoutSession(profile.id, plan_slug);

      console.log('[PAYWALL] checkout_session_created', {
        session_id: result.session_id,
        correlation_id: result.correlation_id,
      });

      await Linking.openURL(result.checkout_url);
    } catch (err: any) {
      console.error('[PAYWALL] checkout_error', err?.message);
      setCheckoutError('Não foi possível iniciar o checkout. Tente novamente.');
    } finally {
      setCheckoutLoading(false);
    }
  }

  if (loadingBilling) {
    return (
      <View style={styles.container}>
        <ActivityIndicator size="large" color="#D4AF37" />
        <Text style={styles.loadingText}>Carregando informações de acesso...</Text>
      </View>
    );
  }

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <Text style={styles.title}>Acesso Restrito</Text>
      <Text style={styles.subtitle}>
        Seu acesso ao Quartel Digital está pendente de liberação.
      </Text>

      {/* Status atual do billing */}
      {billing && !billingError && (
        <View style={styles.card}>
          {billing.plano_atual && (
            <View style={styles.row}>
              <Text style={styles.label}>Plano</Text>
              <Text style={styles.value}>{billing.plano_atual}</Text>
            </View>
          )}
          {billing.status_assinatura && (
            <>
              <View style={styles.divider} />
              <View style={styles.row}>
                <Text style={styles.label}>Status</Text>
                <Text style={styles.value}>{billing.status_assinatura}</Text>
              </View>
            </>
          )}
          {billing.validade && (
            <>
              <View style={styles.divider} />
              <View style={styles.row}>
                <Text style={styles.label}>Validade</Text>
                <Text style={styles.value}>{billing.validade}</Text>
              </View>
            </>
          )}
          {billing.trial_restante !== null && (
            <>
              <View style={styles.divider} />
              <View style={styles.row}>
                <Text style={styles.label}>Trial Restante</Text>
                <Text style={styles.value}>{billing.trial_restante} dia(s)</Text>
              </View>
            </>
          )}
        </View>
      )}

      {billingError && <Text style={styles.errorText}>{billingError}</Text>}

      {/* Planos disponíveis */}
      <Text style={styles.sectionTitle}>Continue o treinamento</Text>

      {PLANS.map((plan) => (
        <TouchableOpacity
          key={plan.slug}
          style={styles.planButton}
          onPress={() => iniciarCheckout(plan.slug)}
          disabled={checkoutLoading}
        >
          {checkoutLoading ? (
            <ActivityIndicator color="#0F0F13" />
          ) : (
            <>
              <Text style={styles.planLabel}>{plan.label}</Text>
              <Text style={styles.planDescription}>{plan.description}</Text>
            </>
          )}
        </TouchableOpacity>
      ))}

      {checkoutError && <Text style={styles.errorText}>{checkoutError}</Text>}

      {/* Verificar acesso (após webhook processar) */}
      <TouchableOpacity style={styles.verifyButton} onPress={retriggerGate}>
        <Text style={styles.verifyText}>Verificar Acesso</Text>
      </TouchableOpacity>

      <TouchableOpacity
        style={[styles.verifyButton, styles.logoutButton]}
        onPress={async () => await signOut()}
      >
        <Text style={styles.logoutText}>Sair</Text>
      </TouchableOpacity>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    flexGrow: 1,
    backgroundColor: '#0F0F13',
    justifyContent: 'center',
    alignItems: 'center',
    padding: 24,
    paddingBottom: 48,
  },
  title: {
    fontSize: 26,
    fontWeight: 'bold',
    color: '#ECECEC',
    marginBottom: 8,
    textAlign: 'center',
  },
  subtitle: {
    fontSize: 14,
    color: '#A1A1AA',
    textAlign: 'center',
    marginBottom: 24,
  },
  loadingText: {
    color: '#A1A1AA',
    marginTop: 16,
    fontSize: 14,
  },
  card: {
    width: '100%',
    backgroundColor: '#1C1C24',
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#3F3F46',
    padding: 20,
    marginBottom: 24,
  },
  row: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 8,
  },
  divider: {
    height: 1,
    backgroundColor: '#3F3F46',
  },
  label: {
    fontSize: 14,
    color: '#A1A1AA',
  },
  value: {
    fontSize: 16,
    fontWeight: '600',
    color: '#ECECEC',
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#ECECEC',
    alignSelf: 'flex-start',
    marginBottom: 12,
  },
  planButton: {
    backgroundColor: '#D4AF37',
    borderRadius: 10,
    paddingVertical: 16,
    paddingHorizontal: 20,
    width: '100%',
    alignItems: 'center',
    marginBottom: 12,
    minHeight: 60,
    justifyContent: 'center',
  },
  planLabel: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#0F0F13',
  },
  planDescription: {
    fontSize: 12,
    color: '#2a2a10',
    marginTop: 2,
  },
  errorText: {
    color: '#EF4444',
    fontSize: 14,
    marginBottom: 16,
    textAlign: 'center',
  },
  verifyButton: {
    backgroundColor: 'transparent',
    borderWidth: 1,
    borderColor: '#3F3F46',
    paddingHorizontal: 24,
    paddingVertical: 14,
    borderRadius: 8,
    width: '100%',
    alignItems: 'center',
    marginTop: 8,
    marginBottom: 12,
  },
  verifyText: {
    color: '#A1A1AA',
    fontSize: 14,
    fontWeight: '600',
  },
  logoutButton: {
    borderColor: '#2a1a1a',
  },
  logoutText: {
    color: '#6B7280',
    fontSize: 14,
    fontWeight: '600',
  },
});
