import { useRouter } from 'expo-router';
import IntroScreen from '../../src/screens/IntroScreen';

export default function Intro() {
    const router = useRouter();

    return (
        <IntroScreen
            onLogin={() => router.push('/(auth)/login')}
            onRegister={() => console.log('Register pressed')}
        />
    );
}
