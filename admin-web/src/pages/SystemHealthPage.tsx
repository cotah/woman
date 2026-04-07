import React, { useState, useEffect, useCallback } from 'react';
import { format } from 'date-fns';
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from 'recharts';
import api from '../services/api';
import { usePolling } from '../hooks/usePolling';
import { LoadingSpinner } from '../components/common/LoadingSpinner';
import type { SystemHealthStatus, ServiceHealth } from '../types';

const HEALTH_COLORS: Record<string, string> = {
  healthy: '#16a34a',
  degraded: '#d97706',
  down: '#dc2626',
};

const HEALTH_BG: Record<string, string> = {
  healthy: '#f0fdf4',
  degraded: '#fffbeb',
  down: '#fef2f2',
};

const cardStyle: React.CSSProperties = {
  background: '#fff',
  borderRadius: 12,
  padding: 20,
  border: '1px solid #e5e7eb',
};

export const SystemHealthPage: React.FC = () => {
  const [health, setHealth] = useState<SystemHealthStatus | null>(null);
  const [loading, setLoading] = useState(true);

  const fetchHealth = useCallback(async () => {
    try {
      const { data } = await api.get<SystemHealthStatus>('/admin/system/health');
      setHealth(data);
    } catch {
      // handled
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchHealth();
  }, [fetchHealth]);

  usePolling(fetchHealth, 10000);

  if (loading) return <LoadingSpinner message="Checking system health..." />;

  if (!health) {
    return (
      <div style={{ textAlign: 'center', padding: 40, color: '#dc2626' }}>
        Unable to reach health endpoint
      </div>
    );
  }

  const latencyData = health.services.map((svc) => ({
    name: svc.name,
    latency: svc.latencyMs,
    fill: HEALTH_COLORS[svc.status],
  }));

  return (
    <div>
      <h1 style={{ fontSize: 22, fontWeight: 700, color: '#111827', marginBottom: 20 }}>
        System Health
      </h1>

      {/* Overall Status */}
      <div
        style={{
          ...cardStyle,
          display: 'flex',
          alignItems: 'center',
          gap: 16,
          marginBottom: 20,
          borderLeft: `4px solid ${HEALTH_COLORS[health.overall]}`,
        }}
      >
        <div
          style={{
            width: 48,
            height: 48,
            borderRadius: '50%',
            background: HEALTH_BG[health.overall],
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            fontSize: 24,
          }}
        >
          {health.overall === 'healthy' ? '\u2705' : health.overall === 'degraded' ? '\u26A0\uFE0F' : '\u274C'}
        </div>
        <div>
          <div style={{ fontSize: 20, fontWeight: 700, color: HEALTH_COLORS[health.overall] }}>
            {health.overall.toUpperCase()}
          </div>
          <div style={{ fontSize: 13, color: '#6b7280' }}>
            {health.services.filter((s) => s.status === 'healthy').length}/{health.services.length} services healthy
          </div>
        </div>
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginBottom: 20 }}>
        {/* Latency Chart */}
        <div style={cardStyle}>
          <h3 style={{ fontSize: 15, fontWeight: 600, marginBottom: 16, color: '#111827' }}>
            Service Latency (ms)
          </h3>
          <ResponsiveContainer width="100%" height={280}>
            <BarChart data={latencyData} layout="vertical" margin={{ left: 20 }}>
              <CartesianGrid strokeDasharray="3 3" stroke="#f3f4f6" />
              <XAxis type="number" tick={{ fontSize: 11 }} />
              <YAxis type="category" dataKey="name" tick={{ fontSize: 12 }} width={100} />
              <Tooltip
                contentStyle={{ borderRadius: 8, border: '1px solid #e5e7eb', fontSize: 12 }}
              />
              <Bar dataKey="latency" radius={[0, 4, 4, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>

        {/* Service List */}
        <div style={cardStyle}>
          <h3 style={{ fontSize: 15, fontWeight: 600, marginBottom: 16, color: '#111827' }}>
            Service Details
          </h3>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {health.services.map((svc: ServiceHealth) => (
              <div
                key={svc.name}
                style={{
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'space-between',
                  padding: '12px 14px',
                  borderRadius: 10,
                  background: HEALTH_BG[svc.status],
                  border: `1px solid ${HEALTH_COLORS[svc.status]}20`,
                }}
              >
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <div
                    style={{
                      width: 10,
                      height: 10,
                      borderRadius: '50%',
                      background: HEALTH_COLORS[svc.status],
                    }}
                  />
                  <div>
                    <div style={{ fontSize: 14, fontWeight: 600, color: '#111827' }}>{svc.name}</div>
                    {svc.message && (
                      <div style={{ fontSize: 11, color: '#6b7280', marginTop: 2 }}>{svc.message}</div>
                    )}
                  </div>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div style={{ fontSize: 14, fontWeight: 600, color: HEALTH_COLORS[svc.status] }}>
                    {svc.latencyMs}ms
                  </div>
                  <div style={{ fontSize: 10, color: '#9ca3af' }}>
                    {format(new Date(svc.lastChecked), 'HH:mm:ss')}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};
