import { createContext, useContext } from 'react';

interface BootstrapGateContextType {
  retriggerGate: () => void;
}

export const BootstrapGateContext = createContext<BootstrapGateContextType | null>(null);

export function useBootstrapGate(): BootstrapGateContextType {
  const ctx = useContext(BootstrapGateContext);
  if (!ctx) {
    throw new Error('useBootstrapGate deve ser usado dentro do BootstrapGate');
  }
  return ctx;
}
