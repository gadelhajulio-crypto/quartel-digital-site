import React from 'react';
import { ViewStyle } from 'react-native';
import { obsidiana } from '../themes/obsidiana';
import { ScreenContainer } from './ScreenContainer';

type Props = {
  children: React.ReactNode;
  scrollable?: boolean;
  avoidKeyboard?: boolean;
  style?: ViewStyle;
  contentStyle?: ViewStyle;
};

/**
 * Layout padrão para telas com tema Obsidiana (dark premium).
 * Usa o tema obsidiana sem necessitar de props de tema.
 */
export function ObsidianScreen({ children, ...rest }: Props) {
  return (
    <ScreenContainer theme={obsidiana} {...rest}>
      {children}
    </ScreenContainer>
  );
}
