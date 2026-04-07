import React from 'react';
import type { IncidentStatus } from '../../types';

const STATUS_CONFIG: Record<IncidentStatus, { bg: string; color: string; label: string }> = {
  active: { bg: '#fef2f2', color: '#dc2626', label: 'Active' },
  monitoring: { bg: '#fffbeb', color: '#d97706', label: 'Monitoring' },
  escalated: { bg: '#fef2f2', color: '#b91c1c', label: 'Escalated' },
  resolved: { bg: '#f0fdf4', color: '#16a34a', label: 'Resolved' },
  false_alarm: { bg: '#f3f4f6', color: '#6b7280', label: 'False Alarm' },
  cancelled: { bg: '#f3f4f6', color: '#9ca3af', label: 'Cancelled' },
};

export const IncidentStatusBadge: React.FC<{ status: IncidentStatus }> = ({ status }) => {
  const config = STATUS_CONFIG[status] || STATUS_CONFIG.active;
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
