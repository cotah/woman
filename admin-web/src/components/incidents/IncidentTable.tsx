import React from 'react';
import { useNavigate } from 'react-router-dom';
import { format, formatDistanceToNow } from 'date-fns';
import { DataTable, Column } from '../common/DataTable';
import { IncidentStatusBadge } from './IncidentStatusBadge';
import { RiskLevelBadge } from './RiskLevelBadge';
import type { Incident } from '../../types';

const TRIGGER_LABELS: Record<string, string> = {
  manual_sos: 'Manual SOS',
  voice_keyword: 'Voice Keyword',
  inactivity: 'Inactivity',
  geofence: 'Geofence',
  shake_detection: 'Shake',
  scheduled_checkin: 'Check-in',
};

interface IncidentTableProps {
  incidents: Incident[];
}

export const IncidentTable: React.FC<IncidentTableProps> = ({ incidents }) => {
  const navigate = useNavigate();

  const columns: Column<Incident>[] = [
    {
      key: 'id',
      header: 'ID',
      width: '100px',
      render: (row) => (
        <span style={{ fontFamily: 'monospace', fontSize: 12 }}>
          {row.id.slice(0, 8)}
          {row.isTestMode && (
            <span
              style={{
                marginLeft: 6,
                padding: '1px 5px',
                borderRadius: 4,
                fontSize: 10,
                background: '#dbeafe',
                color: '#2563eb',
              }}
            >
              TEST
            </span>
          )}
        </span>
      ),
    },
    {
      key: 'userName',
      header: 'User',
      render: (row) => row.userName,
      sortable: true,
    },
    {
      key: 'status',
      header: 'Status',
      render: (row) => <IncidentStatusBadge status={row.status} />,
    },
    {
      key: 'riskLevel',
      header: 'Risk',
      render: (row) => <RiskLevelBadge level={row.riskLevel} />,
    },
    {
      key: 'triggerType',
      header: 'Trigger',
      render: (row) => TRIGGER_LABELS[row.triggerType] || row.triggerType,
    },
    {
      key: 'startedAt',
      header: 'Started',
      sortable: true,
      render: (row) => (
        <span title={format(new Date(row.startedAt), 'PPpp')}>
          {formatDistanceToNow(new Date(row.startedAt), { addSuffix: true })}
        </span>
      ),
    },
    {
      key: 'duration',
      header: 'Duration',
      render: (row) => {
        const end = row.resolvedAt ? new Date(row.resolvedAt) : new Date();
        const diffMs = end.getTime() - new Date(row.startedAt).getTime();
        const mins = Math.floor(diffMs / 60000);
        if (mins < 60) return `${mins}m`;
        return `${Math.floor(mins / 60)}h ${mins % 60}m`;
      },
    },
    {
      key: 'contacts',
      header: 'Contacts',
      render: (row) => (
        <span>
          {row.contactsResponded}/{row.contactsNotified}
        </span>
      ),
    },
  ];

  return (
    <DataTable
      columns={columns}
      data={incidents}
      rowKey={(row) => row.id}
      onRowClick={(row) => navigate(`/incidents/${row.id}`)}
      emptyMessage="No incidents match the current filters"
    />
  );
};
