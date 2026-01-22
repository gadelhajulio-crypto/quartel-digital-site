import React from 'react';
import { Ionicons } from '@expo/vector-icons';

interface IconProps {
    active: boolean;
    color: string;
}

export default function ContinuarIcon({ active, color }: IconProps) {
    return (
        <Ionicons
            name={active ? "play-circle" : "play-circle-outline"}
            size={28}
            color={active ? color : "#666"}
        />
    );
}
