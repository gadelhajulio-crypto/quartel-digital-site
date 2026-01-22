import { ExpoRoot } from "expo-router";
import { registerRootComponent } from "expo";

export default function App() {
  return <ExpoRoot context={require.context("./app")} />;
}

registerRootComponent(App);
