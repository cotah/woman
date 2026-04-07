import React from 'react';
import { format } from 'date-fns';
import type { TimelineEvent } from '../../types';

const EVENT_ICONS: Record<string, string> = {
  incident_started: '\u{1F6A8}',
  location_update: '\u{1F4CD}',
  audio_recording: '\u{1F3A4}',
  alert_sent: '\u{1F4E8}',
  contact_responded: '\u{1F464}',
  risk_escalated: '\u26A0\uFE0F',
  resolution: '\u2705',
  system: '\u2699\uFE0F',
};

interface TimelineViewProps {
  events: TimelineEvent[];
}

export const TimelineView: React.FC<TimelineViewProps> = ({ events }) => {
  return (
    <div style={{ position: 'relative', paddingLeft: 28 }}>
      {/* Vertical line */}
      <div
        style={{
          position: 'absolute',
          left: 11,
          top: 0,
          bottom: 0,
          width: 2,
          background: '#e5e7eb',
        }}
      />
      {events.map((event, index) => (
        <div
          key={event.id}
          style={{
            position: 'relative',
            paddingBottom: index < events.length - 1 ? 20 : 0,
          }}
        >
          {/* Dot */}
          <div
            style={{
              position: 'absolute',
              left: -22,
              top: 2,
              width: 12,
              height: 12,
              borderRadius: '50%',
              background: '#fff',
              border: '2px solid #6366f1',
              zIndex: 1,
            }}
          />
          <div
            style={{
              background: '#f9fafb',
              borderRadius: 8,
              padding: '10px 14px',
              border: '1px solid #f3f4f6',
            }}
          >
            <div
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                marginBottom: 4,
              }}
            >
              <span style={{ fontWeight: 600, fontSize: 13, color: '#111827' }}>
                {EVENT_ICONS[event.type] || '\u2022'} {event.title}
              </span>
              <span style={{ fontSize: 11, color: '#9ca3af', whiteSpace: 'nowrap' }}>
                {format(new Date(event.timestamp), 'HH:mm:ss')}
              </span>
            </div>
            <p style={{ fontSize: 12, color: '#6b7280', margin: 0 }}>
              {event.description}
            </p>
          </div>
        </div>
      ))}
      {events.length === 0 && (
        <p style={{ color: '#9ca3af', fontSize: 13 }}>No timeline events</p>
      )}
    </div>
  );
};
