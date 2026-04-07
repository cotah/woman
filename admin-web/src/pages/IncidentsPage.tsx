import React, { useState, useEffect, useCallback } from 'react';
import api from '../services/api';
import { usePolling } from '../hooks/usePolling';
import { IncidentTable } from '../components/incidents/IncidentTable';
import { Pagination } from '../components/common/Pagination';
import { LoadingSpinner } from '../components/common/LoadingSpinner';
import type { Incident, IncidentFilters, IncidentStatus, RiskLevel, PaginatedResponse } from '../types';

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

const selectStyle: React.CSSProperties = {
  padding: '7px 12px',
  borderRadius: 8,
  border: '1px solid #d1d5db',
  fontSize: 13,
  color: '#374151',
  background: '#fff',
};

const inputStyle: React.CSSProperties = {
  ...selectStyle,
  width: 140,
};

export const IncidentsPage: React.FC = () => {
  const [filters, setFilters] = useState<IncidentFilters>({
    page: 1,
    pageSize: 25,
  });
  const [result, setResult] = useState<PaginatedResponse<Incident> | null>(null);
  const [loading, setLoading] = useState(true);

  const fetchIncidents = useCallback(async () => {
    try {
      const params: Record<string, unknown> = { ...filters };
      // Remove undefined params
      Object.keys(params).forEach((k) => {
        if (params[k] === undefined || params[k] === '') delete params[k];
      });
      const { data } = await api.get<PaginatedResponse<Incident>>('/admin/incidents', { params });
      setResult(data);
    } catch {
      // handled by interceptor
    } finally {
      setLoading(false);
    }
  }, [filters]);

  useEffect(() => {
    setLoading(true);
    fetchIncidents();
  }, [fetchIncidents]);

  usePolling(fetchIncidents, 15000);

  const updateFilter = (key: keyof IncidentFilters, value: unknown) => {
    setFilters((prev) => ({ ...prev, [key]: value || undefined, page: 1 }));
  };

  return (
    <div>
      <h1 style={{ fontSize: 22, fontWeight: 700, color: '#111827', marginBottom: 20 }}>
        Incidents
      </h1>

      {/* Filters */}
      <div style={filterBar}>
        <select
          style={selectStyle}
          value={filters.status || ''}
          onChange={(e) => updateFilter('status', e.target.value as IncidentStatus)}
        >
          <option value="">All Statuses</option>
          <option value="active">Active</option>
          <option value="monitoring">Monitoring</option>
          <option value="escalated">Escalated</option>
          <option value="resolved">Resolved</option>
          <option value="false_alarm">False Alarm</option>
          <option value="cancelled">Cancelled</option>
        </select>

        <select
          style={selectStyle}
          value={filters.riskLevel || ''}
          onChange={(e) => updateFilter('riskLevel', e.target.value as RiskLevel)}
        >
          <option value="">All Risk Levels</option>
          <option value="low">Low</option>
          <option value="medium">Medium</option>
          <option value="high">High</option>
          <option value="critical">Critical</option>
        </select>

        <input
          type="date"
          style={inputStyle}
          value={filters.dateFrom || ''}
          onChange={(e) => updateFilter('dateFrom', e.target.value)}
          placeholder="From"
        />
        <input
          type="date"
          style={inputStyle}
          value={filters.dateTo || ''}
          onChange={(e) => updateFilter('dateTo', e.target.value)}
          placeholder="To"
        />

        <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 13, color: '#374151' }}>
          <input
            type="checkbox"
            checked={filters.testMode === true}
            onChange={(e) => updateFilter('testMode', e.target.checked || undefined)}
          />
          Include test mode
        </label>

        <input
          type="text"
          style={{ ...inputStyle, width: 200 }}
          placeholder="Search user name..."
          value={filters.search || ''}
          onChange={(e) => updateFilter('search', e.target.value)}
        />

        <span style={{ fontSize: 12, color: '#9ca3af', marginLeft: 'auto' }}>
          {result ? `${result.total} total` : ''}
        </span>
      </div>

      {/* Table */}
      <div style={{ background: '#fff', borderRadius: 12, border: '1px solid #e5e7eb' }}>
        {loading && !result ? (
          <LoadingSpinner />
        ) : (
          <>
            <IncidentTable incidents={result?.data || []} />
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
