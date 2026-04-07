import React from 'react';
import type { RiskLevel } from '../../types';

const RISK_CONFIG: Record<RiskLevel, { bg: string; color: string; label: string }> = {
  low: { bg: '#f0fdf4', color: '#16a34a', label: 'Low' },
  medium: { bg: '#fffbeb', color: '#d97706', label: 'Medium' },
  high: { bg: '#fff7ed', color: '#ea580c', label: 'High' },
  critical: { bg: '#fef2f2', color: '#dc2626', label: 'Critical' },
};

export const RiskLevelBadge: React.FC<{ level: RiskLevel }> = ({ level }) => {
  const config = RISK_CONFIG[level] || RISK_CONFIG.low;
  return (
    <span
      style={{
        display: 'inline-block',
        padding: '2px 10px',
        borderRadius: 999,
        fontSize: 12,
        fontWeight: 600,
        background: config.bg,
        color: config.color,
      }}
    >
      {config.label}
    </span>
  );
};
