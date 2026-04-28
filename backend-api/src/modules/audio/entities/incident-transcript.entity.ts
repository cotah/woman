import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
  Index,
} from 'typeorm';
import { Incident } from '@/modules/incidents/entities/incident.entity';
import { IncidentAudioAsset } from './incident-audio-asset.entity';

@Entity('incident_transcripts')
@Index('idx_transcripts_incident', ['incidentId'])
@Index('idx_transcripts_audio', ['audioAssetId'])
export class IncidentTranscript {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'audio_asset_id', type: 'uuid' })
  audioAssetId: string;

  @ManyToOne(() => IncidentAudioAsset, { eager: false })
  @JoinColumn({ name: 'audio_asset_id' })
  audioAsset: IncidentAudioAsset;

  @Column({ name: 'incident_id', type: 'uuid' })
  incidentId: string;

  @ManyToOne(() => Incident, { eager: false })
  @JoinColumn({ name: 'incident_id' })
  incident: Incident;

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
