import React, { useState } from 'react';
import { View, Text, TextInput, StyleSheet, TextInputProps, ViewStyle } from 'react-native';
import { obsidiana } from '../themes/obsidiana';
import { typographyPresets, fontFamily } from '../tokens/typography';

type Theme = typeof obsidiana;

type Props = TextInputProps & {
  label?: string;
  hint?: string;
  error?: string;
  theme?: Theme;
  containerStyle?: ViewStyle;
  rightElement?: React.ReactNode;
};

export function InstitutionalInput({
  label,
  hint,
  error,
  theme = obsidiana,
  containerStyle,
  rightElement,
  ...inputProps
}: Props) {
  const [focused, setFocused] = useState(false);

  const borderColor = error
    ? theme.colors.error
    : focused
    ? theme.colors.accent
    : theme.colors.border;

  return (
    <View style={[styles.container, containerStyle]}>
      {label && (
        <Text style={[typographyPresets.label, { color: theme.colors.textSecondary, marginBottom: 6 }]}>
          {label}
        </Text>
      )}

      <View
        style={[
          styles.inputRow,
          {
            backgroundColor: theme.colors.surface,
            borderColor,
            borderRadius: theme.radius.s,
          },
        ]}
      >
        <TextInput
          placeholderTextColor={theme.colors.muted}
          {...inputProps}
          onFocus={(e) => {
            setFocused(true);
            inputProps.onFocus?.(e);
          }}
          onBlur={(e) => {
            setFocused(false);
            inputProps.onBlur?.(e);
          }}
          style={[
            styles.input,
            {
              color: theme.colors.text,
              fontFamily: fontFamily.regular,
              paddingHorizontal: theme.spacing.m,
              paddingVertical: theme.spacing.s + 4,
            },
            inputProps.style,
          ]}
        />
        {rightElement && (
          <View style={[styles.rightElement, { paddingRight: theme.spacing.m }]}>
            {rightElement}
          </View>
        )}
      </View>

      {(hint || error) && (
        <Text
          style={[
            typographyPresets.bodySmall,
            {
              color: error ? theme.colors.error : theme.colors.muted,
              marginTop: 4,
            },
          ]}
        >
          {error ?? hint}
        </Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    width: '100%',
  },
  inputRow: {
    flexDirection: 'row',
    alignItems: 'center',
    borderWidth: 1.5,
  },
  input: {
    flex: 1,
    fontSize: 15,
  },
  rightElement: {
    justifyContent: 'center',
  },
});
