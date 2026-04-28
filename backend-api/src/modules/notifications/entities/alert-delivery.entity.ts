import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  Index,
} from 'typeorm';

export type AlertChannel = 'push' | 'sms' | 'voice_call' | 'email';
export type AlertDeliveryStatus =
  | 'queued'
  | 'sending'
  | 'delivered'
  | 'failed'
  | 'retrying';

@Entity('alert_deliveries')
@Index('idx_alert_deliveries_incident', ['incidentId'])
@Index('idx_alert_deliveries_contact', ['contactId'])
export class AlertDelivery {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'incident_id', type: 'uuid' })
  incidentId: string;

  @Column({ name: 'contact_id', type: 'uuid' })
  contactId: string;

  @Column({
    type: 'enum',
    enum: ['push', 'sms', 'voice_call', 'email'],
  })
  channel: AlertChannel;

  @Column({
    type: 'enum',
    enum: ['queued', 'sending', 'delivered', 'failed', 'retrying'],
    default: 'queued',
  })
  status: AlertDeliveryStatus;

  @Column({ type: 'integer', default: 1 })
  wave: number;

  @Column({ name: 'message_body', type: 'text', nullable: true })
  messageBody: string | null;

  @Column({ name: 'sent_at', type: 'timestamptz', nullable: true })
  sentAt: Date | null;

  @Column({ name: 'delivered_at', type: 'timestamptz', nullable: true })
  deliveredAt: Date | null;

  @Column({ name: 'failed_at', type: 'timestamptz', nullable: true })
  failedAt: Date | null;

  @Column({ name: 'failure_reason', type: 'text', nullable: true })
  failureReason: string | null;

  @Column({ name: 'retry_count', type: 'integer', default: 0 })
  retryCount: number;

  @Column({ name: 'max_retries', type: 'integer', default: 3 })
  maxRetries: number;

  @Column({ name: 'external_id', type: 'varchar', length: 200, nullable: true })
  externalId: string | null;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt: Date;
}
