import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  OneToMany,
  JoinColumn,
  Index,
} from 'typeorm';
import { IncidentEvent } from './incident-event.entity';
import { IncidentLocation } from './incident-location.entity';

export enum IncidentStatus {
  PENDING = 'pending',
  COUNTDOWN = 'countdown',
  ACTIVE = 'active',
  ESCALATED = 'escalated',
  RESOLVED = 'resolved',
  CANCELLED = 'cancelled',
  FALSE_ALARM = 'false_alarm',
  TIMED_OUT = 'timed_out',
}

export enum TriggerType {
  MANUAL_BUTTON = 'manual_button',
  COERCION_PIN = 'coercion_pin',
  PHYSICAL_BUTTON = 'physical_button',
  QUICK_SHORTCUT = 'quick_shortcut',
  WEARABLE = 'wearable',
  VOICE = 'voice',
  GEOFENCE = 'geofence',
  ROUTE_ANOMALY = 'route_anomaly',
}

export enum RiskLevel {
  NONE = 'none',
  MONITORING = 'monitoring',
  SUSPICIOUS = 'suspicious',
  ALERT = 'alert',
  CRITICAL = 'critical',
}

@Entity('incidents')
@Index('idx_incidents_user', ['userId'])
@Index('idx_incidents_status', ['status'])
@Index('idx_incidents_created', ['createdAt'])
@Index('idx_incidents_test', ['isTestMode'])
export class Incident {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId: string;

  @Column({
    type: 'enum',
    enum: IncidentStatus,
    default: IncidentStatus.PENDING,
  })
  status: IncidentStatus;

  @Column({
    name: 'trigger_type',
    type: 'enum',
    enum: TriggerType,
  })
  triggerType: TriggerType;

  @Column({ name: 'is_coercion', type: 'boolean', default: false })
  isCoercion: boolean;

  @Column({ name: 'is_test_mode', type: 'boolean', default: false })
  isTestMode: boolean;

  @Column({ name: 'current_risk_score', type: 'integer', default: 0 })
  currentRiskScore: number;

  @Column({
    name: 'current_risk_level',
    type: 'enum',
    enum: RiskLevel,
    default: RiskLevel.NONE,
  })
  currentRiskLevel: RiskLevel;

  @Column({ name: 'escalation_wave', type: 'integer', default: 0 })
  escalationWave: number;

  @Column({ name: 'started_at', type: 'timestamptz', default: () => 'NOW()' })
  startedAt: Date;

  @Column({ name: 'countdown_ends_at', type: 'timestamptz', nullable: true })
  countdownEndsAt: Date | null;

  @Column({ name: 'activated_at', type: 'timestamptz', nullable: true })
  activatedAt: Date | null;

  @Column({ name: 'resolved_at', type: 'timestamptz', nullable: true })
  resolvedAt: Date | null;

  @Column({ name: 'resolution_reason', type: 'text', nullable: true })
  resolutionReason: string | null;

  @Column({ name: 'last_location_at', type: 'timestamptz', nullable: true })
  lastLocationAt: Date | null;

  @Column({ name: 'last_latitude', type: 'double precision', nullable: true })
  lastLatitude: number | null;

  @Column({ name: 'last_longitude', type: 'double precision', nullable: true })
  lastLongitude: number | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt: Date;

  // Relations
  @OneToMany(() => IncidentEvent, (event) => event.incident)
  events: IncidentEvent[];

  @OneToMany(() => IncidentLocation, (location) => location.incident)
  locations: IncidentLocation[];
}
