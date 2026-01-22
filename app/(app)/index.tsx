import { Redirect } from 'expo-router';

export default function AppIndex() {
    // regra já existente no projeto:
    // o painel real é decidido pelo backend
    return <Redirect href="/painel" />;
}
