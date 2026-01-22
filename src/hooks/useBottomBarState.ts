import { usePathname } from 'expo-router';

export function useBottomBarState() {
    const pathname = usePathname();

    return {
        isPanel: pathname === '/' || pathname === '/index' || pathname === '/(app)' || pathname === '/(app)/index',
        isInstructor: pathname.startsWith('/instrutor') || pathname.startsWith('/(app)/instrutor'),
        isProfile: pathname.startsWith('/perfil') || pathname.startsWith('/(app)/perfil'),
    };
}
