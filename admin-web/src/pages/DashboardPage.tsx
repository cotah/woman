import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { format } from 'date-fns';
import api from '../services/api';
import { usePolling } from '../hooks/usePolling';
import { IncidentStatusBadge } from '../components/incidents/IncidentStatusBadge';
import { RiskLevelBadge } from '../components/incidents/RiskLevelBadge';
import { LoadingSpinner } from '../components/common/LoadingSpinner';
import type { DashboardStats, Incident, ServiceHealth } from '../types';

const cardStyle: React.CSSProperties = {
  background: '#fff',
  borderRadius: 12,
  padding: 20,
  border: '1px solid #e5e7eb',
};

const statCard = (color: string): React.CSSProperties => ({
  ...cardStyle,
  borderLeft: `4px solid ${color}`,
});

const HEALTH_COLORS: Record<string, string> = {
  healthy: '#16a34a',
  degraded: '#d97706',
  down: '#dc2626',
};

export const DashboardPage: React.FC = () => {
  const navigate = useNavigate();
  const [stats, setStats] = useState<DashboardStats | null>(null);
  const [recentIncidents, setRecentIncidents] = useState<Incident[]>([]);
  const [loading, setLoading] = useState(true);

  const fetchData = useCallback(async () => {
    try {
      const [statsRes, incidentsRes] = await Promise.all([
        api.get<DashboardStats>('/admin/dashboard/stats'),
        api.get<{ data: Incident[] }>('/admin/incidents', {
          params: { page: 1, pageSize: 10, sort: 'startedAt:desc' },
        }),
      ]);
      setStats(statsRes.data);
      setRecentIncidents(incidentsRes.data.data);
    } catch {
      // handled by interceptor
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchData();
  }, [fetchData]);

  usePolling(fetchData, 15000);

  if (loading) return <LoadingSpinner message="Loading dashboard..." />;

  return (
    <div>
      <h1 style={{ fontSize: 22, fontWeight: 700, color: '#111827', marginBottom: 20 }}>
        Dashboard
      </h1>

      {/* Stat Cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 16, marginBottom: 24 }}>
        <div style={statCard('#dc2626')}>
          <div style={{ fontSize: 12, color: '#6b7280', marginBottom: 4 }}>Active Incidents</div>
          <div style={{ fontSize: 32, fontWeight: 700, color: '#111827' }}>
            {stats?.activeIncidents ?? '--'}
          </div>
        </div>
        <div style={statCard('#6366f1')}>
          <div style={{ fontSize: 12, color: '#6b7280', marginBottom: 4 }}>Total Users</div>
          <div style={{ fontSize: 32, fontWeight: 700, color: '#111827' }}>
            {stats?.totalUsers?.toLocaleString() ?? '--'}
          </div>
        </div>
        <div style={statCard('#d97706')}>
          <div style={{ fontSize: 12, color: '#6b7280', marginBottom: 4 }}>Alerts Sent Today</div>
          <div style={{ fontSize: 32, fontWeight: 700, color: '#111827' }}>
            {stats?.alertsSentToday ?? '--'}
          </div>
        </div>
        <div style={statCard('#16a34a')}>
          <div style={{ fontSize: 12, color: '#6b7280', marginBottom: 4 }}>Incidents Today</div>
          <div style={{ fontSize: 32, fontWeight: 700, color: '#111827' }}>
            {stats?.incidentsToday ?? '--'}
          </div>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 320px', gap: 20 }}>
        {/* Recent Incidents */}
        <div style={cardStyle}>
          <h2 style={{ fontSize: 15, fontWeight: 600, marginBottom: 14, color: '#111827' }}>
            Recent Incidents
          </h2>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
            <thead>
              <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
                <th style={{ textAlign: 'left', padding: '8px 10px', color: '#6b7280', fontSize: 11, textTransform: 'uppercase' }}>User</th>
                <th style={{ textAlign: 'left', padding: '8px 10px', color: '#6b7280', fontSize: 11, textTransform: 'uppercase' }}>Status</th>
                <th style={{ textAlign: 'left', padding: '8px 10px', color: '#6b7280', fontSize: 11, textTransform: 'uppercase' }}>Risk</th>
                <th style={{ textAlign: 'left', padding: '8px 10px', color: '#6b7280', fontSize: 11, textTransform: 'uppercase' }}>Started</th>
              </tr>
            </thead>
            <tbody>
              {recentIncidents.map((inc) => (
                <tr
                  key={inc.id}
                  onClick={() => navigate(`/incidents/${inc.id}`)}
                  style={{ cursor: 'pointer', borderBottom: '1px solid #f3f4f6' }}
                  onMouseEnter={(e) => (e.currentTarget.style.background = '#f9fafb')}
                  onMouseLeave={(e) => (e.currentTarget.style.background = '')}
                >
                  <td style={{ padding: '8px 10px' }}>{inc.userName}</td>
                  <td style={{ padding: '8px 10px' }}><IncidentStatusBadge status={inc.status} /></td>
                  <td style={{ padding: '8px 10px' }}><RiskLevelBadge level={inc.riskLevel} /></td>
                  <td style={{ padding: '8px 10px', color: '#6b7280', fontSize: 12 }}>
                    {format(new Date(inc.startedAt), 'MMM d, HH:mm')}
                  </td>
                </tr>
              ))}
              {recentIncidents.length === 0 && (
                <tr>
                  <td colSpan={4} style={{ padding: 20, textAlign: 'center', color: '#9ca3af' }}>
                    No recent incidents
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        {/* System Health */}
        <div style={cardStyle}>
          <h2 style={{ fontSize: 15, fontWeight: 600, marginBottom: 14, color: '#111827' }}>
            System Health
          </h2>
          {stats?.systemHealth ? (
            <>
              <div
                style={{
                  display: 'inline-block',
                  padding: '4px 12px',
                  borderRadius: 999,
                  fontSize: 13,
                  fontWeight: 600,
                  background: stats.systemHealth.overall === 'healthy' ? '#f0fdf4' : stats.systemHealth.overall === 'degraded' ? '#fffbeb' : '#fef2f2',
                  color: HEALTH_COLORS[stats.systemHealth.overall],
                  marginBottom: 16,
                }}
              >
                {stats.systemHealth.overall.toUpperCase()}
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {stats.systemHealth.services.map((svc: ServiceHealth) => (
                  <div
                    key={svc.name}
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      justifyContent: 'space-between',
                      padding: '8px 10px',
                      borderRadius: 8,
                      background: '#f9fafb',
                    }}
                  >
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <div
                        style={{
                          width: 8,
                          height: 8,
                          borderRadius: '50%',
                          background: HEALTH_COLORS[svc.status],
                        }}
                      />
                      <span style={{ fontSize: 13, color: '#374151' }}>{svc.name}</span>
                    </div>
                    <span style={{ fontSize: 11, color: '#9ca3af' }}>{svc.latencyMs}ms</span>
                  </div>
                ))}
              </div>
            </>
          ) : (
            <p style={{ color: '#9ca3af', fontSize: 13 }}>Loading health data...</p>
          )}
        </div>
      </div>
    </div>
  );
};
