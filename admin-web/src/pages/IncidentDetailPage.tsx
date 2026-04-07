import React, { useState, useEffect, useCallback } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { format } from 'date-fns';
import api from '../services/api';
import { usePolling } from '../hooks/usePolling';
import { IncidentStatusBadge } from '../components/incidents/IncidentStatusBadge';
import { RiskLevelBadge } from '../components/incidents/RiskLevelBadge';
import { TimelineView } from '../components/timeline/TimelineView';
import { LoadingSpinner } from '../components/common/LoadingSpinner';
import type { IncidentDetail, AlertDelivery, ContactResponse, AudioAsset } from '../types';

const cardStyle: React.CSSProperties = {
  background: '#fff',
  borderRadius: 12,
  padding: 20,
  border: '1px solid #e5e7eb',
  marginBottom: 16,
};

const sectionTitle: React.CSSProperties = {
  fontSize: 15,
  fontWeight: 600,
  color: '#111827',
  marginBottom: 12,
};

const kv: React.CSSProperties = {
  display: 'grid',
  gridTemplateColumns: '140px 1fr',
  gap: '6px 12px',
  fontSize: 13,
};

const kvLabel: React.CSSProperties = { color: '#6b7280', fontWeight: 500 };
const kvValue: React.CSSProperties = { color: '#111827' };

const DELIVERY_STATUS_COLORS: Record<string, string> = {
  queued: '#9ca3af',
  sent: '#d97706',
  delivered: '#16a34a',
  failed: '#dc2626',
};

export const IncidentDetailPage: React.FC = () => {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const [incident, setIncident] = useState<IncidentDetail | null>(null);
  const [loading, setLoading] = useState(true);

  const fetchIncident = useCallback(async () => {
    if (!id) return;
    try {
      const { data } = await api.get<IncidentDetail>(`/admin/incidents/${id}`);
      setIncident(data);
    } catch {
      // handled
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    fetchIncident();
  }, [fetchIncident]);

  const isActive = incident?.status === 'active' || incident?.status === 'monitoring' || incident?.status === 'escalated';
  usePolling(fetchIncident, 5000, isActive);

  if (loading) return <LoadingSpinner message="Loading incident..." />;
  if (!incident) {
    return (
      <div style={{ textAlign: 'center', padding: 40, color: '#6b7280' }}>
        Incident not found.{' '}
        <button onClick={() => navigate('/incidents')} style={{ color: '#6366f1', background: 'none', border: 'none', cursor: 'pointer' }}>
          Back to incidents
        </button>
      </div>
    );
  }

  return (
    <div>
      {/* Header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 20 }}>
        <button
          onClick={() => navigate('/incidents')}
          style={{ background: 'none', border: 'none', cursor: 'pointer', fontSize: 14, color: '#6366f1' }}
        >
          &larr; Incidents
        </button>
        <h1 style={{ fontSize: 20, fontWeight: 700, color: '#111827', margin: 0 }}>
          Incident {incident.id.slice(0, 8)}
        </h1>
        <IncidentStatusBadge status={incident.status} />
        <RiskLevelBadge level={incident.riskLevel} />
        {incident.isTestMode && (
          <span style={{ padding: '2px 8px', borderRadius: 4, fontSize: 11, background: '#dbeafe', color: '#2563eb', fontWeight: 600 }}>
            TEST MODE
          </span>
        )}
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 400px', gap: 16, alignItems: 'start' }}>
        <div>
          {/* User Info */}
          <div style={cardStyle}>
            <h3 style={sectionTitle}>User Information</h3>
            <div style={kv}>
              <span style={kvLabel}>Name</span>
              <span style={kvValue}>{incident.userName}</span>
              <span style={kvLabel}>Phone</span>
              <span style={kvValue}>{incident.userPhone}</span>
              <span style={kvLabel}>User ID</span>
              <span style={{ ...kvValue, fontFamily: 'monospace', fontSize: 12 }}>{incident.userId}</span>
              <span style={kvLabel}>Trigger</span>
              <span style={kvValue}>{incident.triggerType.replace(/_/g, ' ')}</span>
              <span style={kvLabel}>Started</span>
              <span style={kvValue}>{format(new Date(incident.startedAt), 'PPpp')}</span>
              {incident.resolvedAt && (
                <>
                  <span style={kvLabel}>Resolved</span>
                  <span style={kvValue}>{format(new Date(incident.resolvedAt), 'PPpp')}</span>
                </>
              )}
            </div>
          </div>

          {/* Map */}
          <div style={cardStyle}>
            <h3 style={sectionTitle}>Location Trail</h3>
            <div
              id="incident-map"
              style={{
                height: 300,
                borderRadius: 8,
                background: '#f3f4f6',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                color: '#9ca3af',
                fontSize: 13,
              }}
            >
              {incident.locationTrail.length > 0 ? (
                <MapDisplay trail={incident.locationTrail} />
              ) : (
                'No location data available'
              )}
            </div>
          </div>

          {/* Audio Assets */}
          {incident.audioAssets.length > 0 && (
            <div style={cardStyle}>
              <h3 style={sectionTitle}>Audio Recordings</h3>
              {incident.audioAssets.map((asset: AudioAsset) => (
                <div
                  key={asset.id}
                  style={{
                    padding: 12,
                    borderRadius: 8,
                    background: '#f9fafb',
                    marginBottom: 8,
                    border: '1px solid #f3f4f6',
                  }}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 8 }}>
                    <span style={{ fontSize: 13, fontWeight: 500 }}>
                      {format(new Date(asset.recordedAt), 'HH:mm:ss')} ({asset.durationSeconds}s)
                    </span>
                    <span
                      style={{
                        fontSize: 11,
                        padding: '1px 6px',
                        borderRadius: 4,
                        background: asset.transcriptStatus === 'completed' ? '#f0fdf4' : '#f3f4f6',
                        color: asset.transcriptStatus === 'completed' ? '#16a34a' : '#6b7280',
                      }}
                    >
                      {asset.transcriptStatus}
                    </span>
                  </div>
                  <audio controls src={asset.url} style={{ width: '100%', height: 32 }} />
                  {asset.transcript && (
                    <div
                      style={{
                        marginTop: 8,
                        padding: 10,
                        borderRadius: 6,
                        background: '#fff',
                        fontSize: 12,
                        color: '#374151',
                        fontStyle: 'italic',
                        border: '1px solid #e5e7eb',
                      }}
                    >
                      "{asset.transcript}"
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}

          {/* Alert Delivery Log */}
          <div style={cardStyle}>
            <h3 style={sectionTitle}>Alert Delivery Log</h3>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
              <thead>
                <tr style={{ borderBottom: '2px solid #e5e7eb' }}>
                  <th style={thStyle}>Contact</th>
                  <th style={thStyle}>Channel</th>
                  <th style={thStyle}>Status</th>
                  <th style={thStyle}>Sent</th>
                  <th style={thStyle}>Delivered</th>
                </tr>
              </thead>
              <tbody>
                {incident.alertLog.map((alert: AlertDelivery) => (
                  <tr key={alert.id} style={{ borderBottom: '1px solid #f3f4f6' }}>
                    <td style={tdStyle}>{alert.contactName}</td>
                    <td style={tdStyle}>
                      <span style={{ textTransform: 'uppercase', fontSize: 11, fontWeight: 600 }}>
                        {alert.channel}
                      </span>
                    </td>
                    <td style={tdStyle}>
                      <span style={{ color: DELIVERY_STATUS_COLORS[alert.status], fontWeight: 600 }}>
                        {alert.status}
                      </span>
                      {alert.failureReason && (
                        <div style={{ fontSize: 11, color: '#dc2626' }}>{alert.failureReason}</div>
                      )}
                    </td>
                    <td style={tdStyle}>{format(new Date(alert.sentAt), 'HH:mm:ss')}</td>
                    <td style={tdStyle}>
                      {alert.deliveredAt ? format(new Date(alert.deliveredAt), 'HH:mm:ss') : '--'}
                    </td>
                  </tr>
                ))}
                {incident.alertLog.length === 0 && (
                  <tr>
                    <td colSpan={5} style={{ ...tdStyle, textAlign: 'center', color: '#9ca3af' }}>
                      No alerts sent
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>

          {/* Contact Responses */}
          {incident.contactResponses.length > 0 && (
            <div style={cardStyle}>
              <h3 style={sectionTitle}>Contact Responses</h3>
              {incident.contactResponses.map((resp: ContactResponse) => (
                <div
                  key={resp.contactId}
                  style={{
                    display: 'flex',
                    justifyContent: 'space-between',
                    padding: '8px 10px',
                    borderRadius: 8,
                    background: '#f9fafb',
                    marginBottom: 6,
                    fontSize: 13,
                  }}
                >
                  <span style={{ fontWeight: 500 }}>{resp.contactName}</span>
                  <span style={{ color: '#6366f1', fontWeight: 600 }}>{resp.response.replace(/_/g, ' ')}</span>
                  <span style={{ color: '#9ca3af', fontSize: 12 }}>
                    {format(new Date(resp.respondedAt), 'HH:mm:ss')}
                  </span>
                </div>
              ))}
            </div>
          )}

          {/* Resolution */}
          {incident.resolution && (
            <div style={{ ...cardStyle, borderLeft: '4px solid #16a34a' }}>
              <h3 style={sectionTitle}>Resolution</h3>
              <div style={kv}>
                <span style={kvLabel}>Resolved by</span>
                <span style={kvValue}>{incident.resolution.resolvedByName} ({incident.resolution.resolvedBy})</span>
                <span style={kvLabel}>Reason</span>
                <span style={kvValue}>{incident.resolution.reason}</span>
                <span style={kvLabel}>Time</span>
                <span style={kvValue}>{format(new Date(incident.resolution.resolvedAt), 'PPpp')}</span>
              </div>
            </div>
          )}
        </div>

        {/* Timeline Sidebar */}
        <div style={{ ...cardStyle, maxHeight: 'calc(100vh - 120px)', overflowY: 'auto', position: 'sticky', top: 20 }}>
          <h3 style={sectionTitle}>Timeline</h3>
          <TimelineView events={incident.timeline} />
        </div>
      </div>
    </div>
  );
};

// Inline table styles
const thStyle: React.CSSProperties = {
  textAlign: 'left',
  padding: '8px 10px',
  color: '#6b7280',
  fontSize: 11,
  textTransform: 'uppercase',
  fontWeight: 600,
};
const tdStyle: React.CSSProperties = {
  padding: '8px 10px',
  color: '#111827',
};

// Simple Leaflet map component
const MapDisplay: React.FC<{ trail: { latitude: number; longitude: number; timestamp: string }[] }> = ({ trail }) => {
  const mapRef = React.useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!mapRef.current || trail.length === 0) return;

    let map: L.Map | null = null;
    import('leaflet').then((L) => {
      if (!mapRef.current) return;
      const center = trail[trail.length - 1];
      map = L.map(mapRef.current).setView([center.latitude, center.longitude], 15);

      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '&copy; OpenStreetMap',
      }).addTo(map);

      // Draw trail
      const latlngs = trail.map((p) => [p.latitude, p.longitude] as [number, number]);
      L.polyline(latlngs, { color: '#6366f1', weight: 3 }).addTo(map);

      // Start marker
      L.circleMarker([trail[0].latitude, trail[0].longitude], {
        radius: 6,
        color: '#16a34a',
        fillColor: '#16a34a',
        fillOpacity: 1,
      })
        .bindPopup('Start')
        .addTo(map);

      // Current/last marker
      L.circleMarker([center.latitude, center.longitude], {
        radius: 8,
        color: '#dc2626',
        fillColor: '#dc2626',
        fillOpacity: 1,
      })
        .bindPopup('Current')
        .addTo(map);

      map.fitBounds(L.latLngBounds(latlngs).pad(0.2));
    });

    return () => {
      map?.remove();
    };
  }, [trail]);

  return <div ref={mapRef} style={{ width: '100%', height: '100%', borderRadius: 8 }} />;
};
