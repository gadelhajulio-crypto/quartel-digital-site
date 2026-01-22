import { ReactNode, useEffect } from 'react';
import { useRouter } from 'expo-router';
import { useAuth } from '../context/AuthContext';
import { InstitutionalLoading } from '../components/InstitutionalLoading';

export function ProtectedRoute({ children }: { children: ReactNode }) {
    const { session, loading } = useAuth();
    const router = useRouter();

    useEffect(() => {
        if (!loading && !session) {
            router.replace('/auth');
        }
    }, [loading, session]);

    if (loading || !session) {
        return <InstitutionalLoading />;
    }

    return <>{children}</>;
}
