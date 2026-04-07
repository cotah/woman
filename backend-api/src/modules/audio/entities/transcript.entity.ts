import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  Index,
} from 'typeorm';

@Entity('incident_transcripts')
@Index('idx_transcripts_incident', ['incidentId'])
@Index('idx_transcripts_audio', ['audioAssetId'])
export class Transcript {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'audio_asset_id', type: 'uuid' })
  audioAssetId: string;

  @Column({ name: 'incident_id', type: 'uuid' })
  incidentId: string;

  @Column({ type: 'text' })
  text: string;

  @Column({ type: 'double precision', default: 0 })
  confidence: number;

  @Column({ type: 'varchar', length: 10, default: 'en' })
  language: string;

  @Column({ name: 'distress_signals', type: 'jsonb', default: '[]' })
  distressSignals: any[];

  @Column({ name: 'ai_summary', type: 'text', nullable: true })
  aiSummary: string | null;

  @Column({ name: 'ai_risk_indicators', type: 'jsonb', nullable: true, default: '[]' })
  aiRiskIndicators: any[];

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt: Date;
}
