import React from 'react';
import { Ionicons } from '@expo/vector-icons';

interface IconProps {
    active: boolean;
    color: string;
}

export default function ProfileIcon({ active, color }: IconProps) {
    return (
        <Ionicons
            name={active ? "person" : "person-outline"}
            size={24}
            color={active ? color : "#666"}
        />
    );
}
