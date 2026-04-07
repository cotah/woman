import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  OneToOne,
  JoinColumn,
} from 'typeorm';
import { User } from '../../users/entities/user.entity';

export enum AudioConsentLevel {
  NONE = 'none',
  RECORD_ONLY = 'record_only',
  RECORD_AND_ANALYZE = 'record_and_analyze',
  FULL = 'full',
}

export enum RiskLevel {
  NONE = 'none',
  MONITORING = 'monitoring',
  SUSPICIOUS = 'suspicious',
  ALERT = 'alert',
  CRITICAL = 'critical',
}

@Entity('emergency_settings')
export class EmergencySettings {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'uuid', name: 'user_id', unique: true })
  userId: string;

  @OneToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user: User;

  @Column({ type: 'integer', name: 'countdown_duration_seconds', default: 5 })
  countdownDurationSeconds: number;

  @Column({ type: 'varchar', length: 255, name: 'coercion_pin_hash', nullable: true, select: false })
  coercionPinHash: string;

  @Column({ type: 'varchar', length: 50, name: 'normal_cancel_method', default: 'tap_pattern' })
  normalCancelMethod: string;

  @Column({
    type: 'enum',
    enum: AudioConsentLevel,
    name: 'audio_consent',
    default: AudioConsentLevel.NONE,
  })
  audioConsent: AudioConsentLevel;

  @Column({ type: 'boolean', name: 'auto_record_audio', default: false })
  autoRecordAudio: boolean;

  @Column({ type: 'boolean', name: 'allow_ai_analysis', default: false })
  allowAiAnalysis: boolean;

  @Column({ type: 'boolean', name: 'share_audio_with_contacts', default: false })
  shareAudioWithContacts: boolean;

  @Column({ type: 'uuid', name: 'audio_contact_ids', array: true, default: '{}' })
  audioContactIds: string[];

  @Column({
    type: 'enum',
    enum: RiskLevel,
    name: 'audio_share_threshold',
    default: RiskLevel.CRITICAL,
  })
  audioShareThreshold: RiskLevel;

  @Column({ type: 'boolean', name: 'enable_test_mode', default: false })
  enableTestMode: boolean;

  @Column({ type: 'jsonb', name: 'trigger_configurations', default: '[]' })
  triggerConfigurations: Record<string, any>[];

  @Column({
    type: 'text',
    name: 'emergency_message',
    default: 'I need help. This is an emergency alert from SafeCircle.',
  })
  emergencyMessage: string;

  @CreateDateColumn({ type: 'timestamptz', name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ type: 'timestamptz', name: 'updated_at' })
  updatedAt: Date;
}
