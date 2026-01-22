import { View } from 'react-native';
import { useEffect } from 'react';
import { InstitutionalError } from '../components/InstitutionalError';
import { InstitutionalLoading } from '../components/InstitutionalLoading';
import { useLesson } from '../hooks/useLesson';
import { VideoPlayer } from '../components/VideoPlayer';

export default function AulaPlayerScreen() {
    const { loading, error, lesson, canPlay } = useLesson();

    useEffect(() => {
        return () => {
            // cleanup defensivo do player (sem lógica nova)
        };
    }, []);

    if (loading) return <InstitutionalLoading />;
    if (error || !lesson) return <InstitutionalError />;
    if (!canPlay) return <InstitutionalError />;

    return (
        <View style={{ flex: 1 }}>
            <VideoPlayer source={lesson.videoUrl} />
        </View>
    );
}
