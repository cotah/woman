import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';

export enum JourneyStatus {
  ACTIVE = 'active',
  COMPLETED = 'completed',
  EXPIRED = 'expired',
  ESCALATED = 'escalated',
  CANCELLED = 'cancelled',
}

@Entity('journeys')
@Index('idx_journeys_user_status', ['userId', 'status'])
export class Journey {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId: string;

  @Column({ type: 'enum', enum: JourneyStatus, default: JourneyStatus.ACTIVE })
  status: JourneyStatus;

  @Column({ name: 'start_latitude', type: 'decimal', precision: 10, scale: 7, nullable: true })
  startLatitude: number;

  @Column({ name: 'start_longitude', type: 'decimal', precision: 10, scale: 7, nullable: true })
  startLongitude: number;

  @Column({ name: 'dest_latitude', type: 'decimal', precision: 10, scale: 7 })
  destLatitude: number;

  @Column({ name: 'dest_longitude', type: 'decimal', precision: 10, scale: 7 })
  destLongitude: number;

  @Column({ name: 'dest_label', nullable: true })
  destLabel: string;

  @Column({ name: 'arrival_radius_meters', type: 'int', default: 200 })
  arrivalRadiusMeters: number;

  @Column({ name: 'duration_minutes', type: 'int' })
  durationMinutes: number;

  @Column({ name: 'expires_at', type: 'timestamptz' })
  expiresAt: Date;

  @Column({ name: 'started_at', type: 'timestamptz' })
  startedAt: Date;

  @Column({ name: 'completed_at', type: 'timestamptz', nullable: true })
  completedAt: Date;

  @Column({ name: 'last_checkin_at', type: 'timestamptz', nullable: true })
  lastCheckinAt: Date;

  @Column({ name: 'incident_id', type: 'uuid', nullable: true })
  incidentId: string;

  @Column({ name: 'is_test_mode', default: false })
  isTestMode: boolean;

  /// Duration the AI estimated for this route based on history (null if no data).
  @Column({ name: 'ai_estimated_minutes', type: 'int', nullable: true })
  aiEstimatedMinutes: number | null;

  /// Whether a safety check-in push was already sent for this journey.
  @Column({ name: 'checkin_sent', default: false })
  checkinSent: boolean;

  /// User's response to the safety check-in push: 'ok' or 'help' or null.
  @Column({ name: 'checkin_response', type: 'varchar', length: 10, nullable: true })
  checkinResponse: string | null;

  /// When the check-in push was sent.
  @Column({ name: 'checkin_sent_at', type: 'timestamptz', nullable: true })
  checkinSentAt: Date | null;

  @CreateDateColumn({ name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at' })
  updatedAt: Date;
}
