import React from 'react';
import { Ionicons } from '@expo/vector-icons';

interface IconProps {
    color: string;
}

export default function InstructorIcon({ color }: IconProps) {
    return (
        <Ionicons name="chatbubbles" size={28} color={color} />
    );
}
