import type { RequireContext } from 'expo-router';

declare global {
    interface NodeRequire {
        context(
            directory: string,
            useSubdirectories?: boolean,
            regExp?: RegExp
        ): RequireContext;
    }
}
