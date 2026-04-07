import React, { useState, useEffect, useCallback } from 'react';
import { format } from 'date-fns';
import api from '../services/api';
import { DataTable, Column } from '../components/common/DataTable';
import { Pagination } from '../components/common/Pagination';
import { LoadingSpinner } from '../components/common/LoadingSpinner';
import type { AuditLogEntry, AuditLogFilters, PaginatedResponse } from '../types';

const filterBar: React.CSSProperties = {
  display: 'flex',
  flexWrap: 'wrap',
  gap: 12,
  alignItems: 'center',
  marginBottom: 16,
  padding: 16,
  background: '#fff',
  borderRadius: 12,
  border: '1px solid #e5e7eb',
};

const inputStyle: React.CSSProperties = {
  padding: '7px 12px',
  borderRadius: 8,
  border: '1px solid #d1d5db',
  fontSize: 13,
  color: '#374151',
  background: '#fff',
};

const ACTION_COLORS: Record<string, string> = {
  create: '#16a34a',
  update: '#d97706',
  delete: '#dc2626',
  login: '#6366f1',
  logout: '#9ca3af',
};

export const AuditLogsPage: React.FC = () => {
  const [filters, setFilters] = useState<AuditLogFilters>({
    page: 1,
    pageSize: 50,
  });
  const [result, setResult] = useState<PaginatedResponse<AuditLogEntry> | null>(null);
  const [loading, setLoading] = useState(true);

  const fetchLogs = useCallback(async () => {
    try {
      const params: Record<string, unknown> = { ...filters };
      Object.keys(params).forEach((k) => {
        if (params[k] === undefined || params[k] === '') delete params[k];
      });
      const { data } = await api.get<PaginatedResponse<AuditLogEntry>>('/admin/audit-logs', { params });
      setResult(data);
    } catch {
      // handled
    } finally {
      setLoading(false);
    }
  }, [filters]);

  useEffect(() => {
    setLoading(true);
    fetchLogs();
  }, [fetchLogs]);

  const updateFilter = (key: keyof AuditLogFilters, value: unknown) => {
    setFilters((prev) => ({ ...prev, [key]: value || undefined, page: 1 }));
  };

  const columns: Column<AuditLogEntry>[] = [
    {
      key: 'timestamp',
      header: 'Time',
      width: '160px',
      sortable: true,
      render: (row) => (
        <span style={{ fontSize: 12, color: '#6b7280' }}>
          {format(new Date(row.timestamp), 'MMM d, HH:mm:ss')}
        </span>
      ),
    },
    {
      key: 'action',
      header: 'Action',
      render: (row) => {
        const base = row.action.split('.')[0];
        return (
          <span
            style={{
              fontWeight: 600,
              fontSize: 12,
              color: ACTION_COLORS[base] || '#374151',
            }}
          >
            {row.action}
          </span>
        );
      },
    },
    {
      key: 'actor',
      header: 'Actor',
      render: (row) => (
        <div>
          <span style={{ fontWeight: 500 }}>{row.actorName}</span>
          <span
            style={{
              marginLeft: 6,
              fontSize: 10,
              padding: '1px 5px',
              borderRadius: 4,
              background: '#f3f4f6',
              color: '#6b7280',
              textTransform: 'uppercase',
            }}
          >
            {row.actorRole}
          </span>
        </div>
      ),
    },
    {
      key: 'target',
      header: 'Target',
      render: (row) => (
        <span style={{ fontFamily: 'monospace', fontSize: 12 }}>
          {row.targetType}/{row.targetId.slice(0, 8)}
        </span>
      ),
    },
    {
      key: 'details',
      header: 'Details',
      render: (row) => {
        const entries = Object.entries(row.details);
        if (entries.length === 0) return <span style={{ color: '#9ca3af' }}>--</span>;
        return (
          <span
            style={{ fontSize: 12, color: '#6b7280', maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', display: 'block' }}
            title={JSON.stringify(row.details, null, 2)}
          >
            {entries.map(([k, v]) => `${k}=${String(v)}`).join(', ')}
          </span>
        );
      },
    },
    {
      key: 'ip',
      header: 'IP',
      width: '120px',
      render: (row) => (
        <span style={{ fontSize: 12, fontFamily: 'monospace', color: '#9ca3af' }}>
          {row.ipAddress}
        </span>
      ),
    },
  ];

  return (
    <div>
      <h1 style={{ fontSize: 22, fontWeight: 700, color: '#111827', marginBottom: 20 }}>
        Audit Logs
      </h1>

      <div style={filterBar}>
        <input
          type="text"
          style={{ ...inputStyle, width: 220 }}
          placeholder="Search actions, actors..."
          value={filters.search || ''}
          onChange={(e) => updateFilter('search', e.target.value)}
        />
        <select
          style={inputStyle}
          value={filters.action || ''}
          onChange={(e) => updateFilter('action', e.target.value)}
        >
          <option value="">All Actions</option>
          <option value="create">Create</option>
          <option value="update">Update</option>
          <option value="delete">Delete</option>
          <option value="login">Login</option>
          <option value="logout">Logout</option>
        </select>
        <select
          style={inputStyle}
          value={filters.targetType || ''}
          onChange={(e) => updateFilter('targetType', e.target.value)}
        >
          <option value="">All Targets</option>
          <option value="incident">Incident</option>
          <option value="user">User</option>
          <option value="feature_flag">Feature Flag</option>
          <option value="system">System</option>
        </select>
        <input
          type="date"
          style={inputStyle}
          value={filters.dateFrom || ''}
          onChange={(e) => updateFilter('dateFrom', e.target.value)}
        />
        <input
          type="date"
          style={inputStyle}
          value={filters.dateTo || ''}
          onChange={(e) => updateFilter('dateTo', e.target.value)}
        />
        <span style={{ fontSize: 12, color: '#9ca3af', marginLeft: 'auto' }}>
          {result ? `${result.total} entries` : ''}
        </span>
      </div>

      <div style={{ background: '#fff', borderRadius: 12, border: '1px solid #e5e7eb' }}>
        {loading && !result ? (
          <LoadingSpinner />
        ) : (
          <>
            <DataTable
              columns={columns}
              data={result?.data || []}
              rowKey={(row) => row.id}
              emptyMessage="No audit log entries found"
            />
            {result && (
              <Pagination
                page={result.page}
                totalPages={result.totalPages}
                onPageChange={(p) => setFilters((prev) => ({ ...prev, page: p }))}
              />
            )}
          </>
        )}
      </div>
    </div>
  );
};
