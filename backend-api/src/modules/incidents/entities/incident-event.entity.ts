import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
  Index,
} from 'typeorm';
import { Incident } from './incident.entity';

export enum IncidentEventType {
  TRIGGER_ACTIVATED = 'trigger_activated',
  COUNTDOWN_STARTED = 'countdown_started',
  COUNTDOWN_CANCELLED = 'countdown_cancelled',
  INCIDENT_ACTIVATED = 'incident_activated',
  COERCION_DETECTED = 'coercion_detected',
  LOCATION_UPDATE = 'location_update',
  AUDIO_CHUNK_UPLOADED = 'audio_chunk_uploaded',
  TRANSCRIPTION_COMPLETED = 'transcription_completed',
  RISK_SCORE_CHANGED = 'risk_score_changed',
  ALERT_DISPATCHED = 'alert_dispatched',
  ALERT_DELIVERED = 'alert_delivered',
  ALERT_FAILED = 'alert_failed',
  CONTACT_RESPONDED = 'contact_responded',
  ESCALATION_WAVE = 'escalation_wave',
  INCIDENT_RESOLVED = 'incident_resolved',
  INCIDENT_TIMED_OUT = 'incident_timed_out',
  SECRET_CANCEL = 'secret_cancel',
  AI_ANALYSIS_RESULT = 'ai_analysis_result',
  NOTE_ADDED = 'note_added',
  GEOFENCE_BREACH = 'geofence_breach',
  ROUTE_DEVIATION = 'route_deviation',
  WEARABLE_SIGNAL = 'wearable_signal',
  OPERATOR_ACTION = 'operator_action',
}

@Entity('incident_events')
@Index('idx_incident_events_incident', ['incidentId', 'timestamp'])
@Index('idx_incident_events_type', ['incidentId', 'type'])
export class IncidentEvent {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'incident_id', type: 'uuid' })
  incidentId: string;

  @Column({
    type: 'enum',
    enum: IncidentEventType,
  })
  type: IncidentEventType;

  @Column({ type: 'timestamptz', default: () => 'NOW()' })
  timestamp: Date;

  @Column({ type: 'jsonb', default: {} })
  payload: Record<string, any>;

  @Column({ type: 'varchar', length: 100, default: 'system' })
  source: string;

  @Column({ name: 'is_internal', type: 'boolean', default: false })
  isInternal: boolean;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt: Date;

  // Relations
  @ManyToOne(() => Incident, (incident) => incident.events)
  @JoinColumn({ name: 'incident_id' })
  incident: Incident;
}
