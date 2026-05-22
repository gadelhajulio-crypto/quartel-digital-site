const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');

const config = getDefaultConfig(__dirname);

// The `assert` npm package (pulled in via expo-notifications → @ide/backoff) requires
// the Node.js `util` polyfill, which Metro fails to resolve in the RN bundle.
// We intercept `assert` before Metro's normal node_modules lookup and redirect it to
// a lightweight RN-compatible stub that satisfies the API surface used at runtime.
const ASSERT_STUB = path.resolve(__dirname, 'src/stubs/assert.js');

const originalResolveRequest = config.resolver.resolveRequest;

config.resolver.resolveRequest = (context, moduleName, platform) => {
  if (moduleName === 'assert') {
    return { filePath: ASSERT_STUB, type: 'sourceFile' };
  }
  if (originalResolveRequest) {
    return originalResolveRequest(context, moduleName, platform);
  }
  return context.resolveRequest(context, moduleName, platform);
};

module.exports = config;
