import { View } from 'react-native';
import { InstitutionalError } from '../components/InstitutionalError';
import { InstitutionalLoading } from '../components/InstitutionalLoading';
import { useRevision } from '../hooks/useRevision';
import { AudioPlayer } from '../components/AudioPlayer';

export default function RevisaoAudioScreen() {
    const { loading, error, revision, canPlay } = useRevision();

    if (loading) return <InstitutionalLoading />;
    if (error || !revision || !canPlay) {
        return <InstitutionalError />;
    }

    return (
        <View style={{ flex: 1 }}>
            <AudioPlayer source={revision.audioUrl} />
        </View>
    );
}
