import React from 'react';
import { ViewStyle } from 'react-native';
import { dossie } from '../themes/dossie';
import { ScreenContainer } from './ScreenContainer';

type Props = {
  children: React.ReactNode;
  scrollable?: boolean;
  avoidKeyboard?: boolean;
  style?: ViewStyle;
  contentStyle?: ViewStyle;
};

/**
 * Layout padrão para telas com tema Dossiê (paper/light institucional).
 * Use em telas de histórico, documentos e revisão.
 */
export function DossierScreen({ children, ...rest }: Props) {
  return (
    <ScreenContainer theme={dossie} {...rest}>
      {children}
    </ScreenContainer>
  );
}
