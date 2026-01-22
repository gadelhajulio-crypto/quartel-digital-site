import { Slot, useRouter } from 'expo-router';
import { useEffect } from 'react';
import { useAuth } from '../src/context/AuthContext';
import { InstitutionalLoading } from '../src/components/InstitutionalLoading';

export default function RootLayout() {
  const { loading, session } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!loading && !session) {
      router.replace('/auth');
    }
  }, [loading, session]);

  if (loading) {
    return <InstitutionalLoading />;
  }

  return <Slot />;
}
