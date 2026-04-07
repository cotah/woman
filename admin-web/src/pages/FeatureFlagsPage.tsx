import React, { useState, useEffect, useCallback } from 'react';
import api from '../services/api';
import { LoadingSpinner } from '../components/common/LoadingSpinner';
import type { FeatureFlag, Phase } from '../types';

const PHASE_CONFIG: Record<Phase, { label: string; color: string; bg: string }> = {
  phase_1: { label: 'Phase 1 - MVP', color: '#6366f1', bg: '#eef2ff' },
  phase_2: { label: 'Phase 2 - Intelligence', color: '#d97706', bg: '#fffbeb' },
  phase_3: { label: 'Phase 3 - Community', color: '#16a34a', bg: '#f0fdf4' },
  phase_4: { label: 'Phase 4 - Integration', color: '#7c3aed', bg: '#f5f3ff' },
};

const cardStyle: React.CSSProperties = {
  background: '#fff',
  borderRadius: 12,
  border: '1px solid #e5e7eb',
  marginBottom: 16,
};

export const FeatureFlagsPage: React.FC = () => {
  const [flags, setFlags] = useState<FeatureFlag[]>([]);
  const [loading, setLoading] = useState(true);
  const [toggling, setToggling] = useState<string | null>(null);

  const fetchFlags = useCallback(async () => {
    try {
      const { data } = await api.get<FeatureFlag[]>('/admin/feature-flags');
      setFlags(data);
    } catch {
      // handled
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchFlags();
  }, [fetchFlags]);

  const toggleFlag = async (flag: FeatureFlag) => {
    setToggling(flag.id);
    try {
      await api.patch(`/admin/feature-flags/${flag.id}`, { enabled: !flag.enabled });
      setFlags((prev) =>
        prev.map((f) => (f.id === flag.id ? { ...f, enabled: !f.enabled } : f))
      );
    } catch {
      // handled
    } finally {
      setToggling(null);
    }
  };

  if (loading) return <LoadingSpinner message="Loading feature flags..." />;

  // Group by phase
  const grouped = flags.reduce(
    (acc, flag) => {
      if (!acc[flag.phase]) acc[flag.phase] = [];
      acc[flag.phase].push(flag);
      return acc;
    },
    {} as Record<Phase, FeatureFlag[]>
  );

  const phases: Phase[] = ['phase_1', 'phase_2', 'phase_3', 'phase_4'];

  return (
    <div>
      <h1 style={{ fontSize: 22, fontWeight: 700, color: '#111827', marginBottom: 20 }}>
        Feature Flags
      </h1>

      {phases.map((phase) => {
        const phaseFlags = grouped[phase];
        if (!phaseFlags || phaseFlags.length === 0) return null;
        const config = PHASE_CONFIG[phase];

        return (
          <div key={phase} style={{ marginBottom: 24 }}>
            <div
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 8,
                padding: '6px 14px',
                borderRadius: 8,
                background: config.bg,
                color: config.color,
                fontSize: 14,
                fontWeight: 600,
                marginBottom: 12,
              }}
            >
              <span
                style={{
                  width: 8,
                  height: 8,
                  borderRadius: '50%',
                  background: config.color,
                }}
              />
              {config.label}
            </div>

            <div style={cardStyle}>
              {phaseFlags.map((flag, idx) => (
                <div
                  key={flag.id}
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'space-between',
                    padding: '14px 20px',
                    borderBottom: idx < phaseFlags.length - 1 ? '1px solid #f3f4f6' : 'none',
                  }}
                >
                  <div style={{ flex: 1 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 2 }}>
                      <span style={{ fontSize: 14, fontWeight: 600, color: '#111827' }}>
                        {flag.name}
                      </span>
                      <code
                        style={{
                          fontSize: 11,
                          padding: '1px 6px',
                          borderRadius: 4,
                          background: '#f3f4f6',
                          color: '#6b7280',
                        }}
                      >
                        {flag.key}
                      </code>
                    </div>
                    <p style={{ fontSize: 12, color: '#6b7280', margin: 0 }}>{flag.description}</p>
                  </div>

                  <div style={{ display: 'flex', alignItems: 'center', gap: 16 }}>
                    {/* Rollout percentage */}
                    <div style={{ textAlign: 'right', minWidth: 60 }}>
                      <div style={{ fontSize: 14, fontWeight: 600, color: '#374151' }}>
                        {flag.rolloutPercentage}%
                      </div>
                      <div style={{ fontSize: 10, color: '#9ca3af' }}>rollout</div>
                    </div>

                    {/* Toggle */}
                    <button
                      onClick={() => toggleFlag(flag)}
                      disabled={toggling === flag.id}
                      style={{
                        width: 48,
                        height: 26,
                        borderRadius: 13,
                        border: 'none',
                        cursor: 'pointer',
                        background: flag.enabled ? '#16a34a' : '#d1d5db',
                        position: 'relative',
                        transition: 'background 0.2s',
                        opacity: toggling === flag.id ? 0.5 : 1,
                      }}
                    >
                      <span
                        style={{
                          position: 'absolute',
                          top: 3,
                          left: flag.enabled ? 24 : 3,
                          width: 20,
                          height: 20,
                          borderRadius: '50%',
                          background: '#fff',
                          transition: 'left 0.2s',
                          boxShadow: '0 1px 3px rgba(0,0,0,0.2)',
                        }}
                      />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          </div>
        );
      })}

      {flags.length === 0 && (
        <div style={{ textAlign: 'center', padding: 40, color: '#9ca3af' }}>
          No feature flags configured
        </div>
      )}
    </div>
  );
};
