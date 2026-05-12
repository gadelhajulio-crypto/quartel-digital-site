import React from 'react';
import { ViewStyle } from 'react-native';
import { tatico } from '../themes/tatico';
import { ScreenContainer } from './ScreenContainer';

type Props = {
  children: React.ReactNode;
  scrollable?: boolean;
  avoidKeyboard?: boolean;
  style?: ViewStyle;
  contentStyle?: ViewStyle;
};

/**
 * Layout padrão para telas com tema Tático (azul-aço operacional).
 * Use em telas de módulos, missões e treino.
 */
export function TacticalScreen({ children, ...rest }: Props) {
  return (
    <ScreenContainer theme={tatico} {...rest}>
      {children}
    </ScreenContainer>
  );
}
