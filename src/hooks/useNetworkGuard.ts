import NetInfo, { NetInfoState } from '@react-native-community/netinfo';
import { useEffect, useState } from 'react';

export function useNetworkGuard() {
    const [online, setOnline] = useState(true);

    useEffect(() => {
        const sub = NetInfo.addEventListener((state: NetInfoState) => {
            setOnline(Boolean(state.isConnected));
        });
        return () => sub();
    }, []);

    return online;
}
