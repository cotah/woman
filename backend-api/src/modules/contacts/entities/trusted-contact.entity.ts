import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  DeleteDateColumn,
  ManyToOne,
  JoinColumn,
  Index,
} from 'typeorm';
import { User } from '../../users/entities/user.entity';

@Entity('trusted_contacts')
@Index('idx_trusted_contacts_user', ['userId'], { where: '"deleted_at" IS NULL' })
@Index('idx_trusted_contacts_priority', ['userId', 'priority'])
export class TrustedContact {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'uuid', name: 'user_id' })
  userId: string;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user: User;

  @Column({ type: 'varchar', length: 200 })
  name: string;

  @Column({ type: 'varchar', length: 100, nullable: true })
  relationship: string;

  @Column({ type: 'varchar', length: 20 })
  phone: string;

  @Column({ type: 'varchar', length: 255, nullable: true })
  email: string;

  @Column({ type: 'integer', default: 1 })
  priority: number;

  @Column({ type: 'boolean', name: 'can_receive_sms', default: true })
  canReceiveSms: boolean;

  @Column({ type: 'boolean', name: 'can_receive_push', default: false })
  canReceivePush: boolean;

  @Column({ type: 'boolean', name: 'can_receive_voice_call', default: false })
  canReceiveVoiceCall: boolean;

  @Column({ type: 'boolean', name: 'can_access_audio', default: false })
  canAccessAudio: boolean;

  @Column({ type: 'boolean', name: 'can_access_location', default: true })
  canAccessLocation: boolean;

  @Column({ type: 'varchar', length: 10, default: 'en' })
  locale: string;

  @Column({ type: 'boolean', name: 'is_verified', default: false })
  isVerified: boolean;

  @Column({ type: 'varchar', length: 100, name: 'verification_token', nullable: true, select: false })
  verificationToken: string;

  @Column({ type: 'timestamptz', name: 'verified_at', nullable: true })
  verifiedAt: Date;

  @DeleteDateColumn({ type: 'timestamptz', name: 'deleted_at' })
  deletedAt: Date;

  @CreateDateColumn({ type: 'timestamptz', name: 'created_at' })
  createdAt: Date;

  @UpdateDateColumn({ type: 'timestamptz', name: 'updated_at' })
  updatedAt: Date;
}
