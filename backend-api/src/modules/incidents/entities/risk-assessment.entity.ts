import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  Index,
} from 'typeorm';
import { RiskLevel } from './incident.entity';

@Entity('incident_risk_assessments')
@Index('idx_risk_assessments_incident', ['incidentId', 'timestamp'])
export class RiskAssessment {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'incident_id', type: 'uuid' })
  incidentId: string;

  @Column({ name: 'previous_score', type: 'integer' })
  previousScore: number;

  @Column({ name: 'new_score', type: 'integer' })
  newScore: number;

  @Column({
    name: 'previous_level',
    type: 'enum',
    enum: RiskLevel,
  })
  previousLevel: RiskLevel;

  @Column({
    name: 'new_level',
    type: 'enum',
    enum: RiskLevel,
  })
  newLevel: RiskLevel;

  @Column({ name: 'rule_id', type: 'varchar', length: 100 })
  ruleId: string;

  @Column({ name: 'rule_name', type: 'varchar', length: 200 })
  ruleName: string;

  @Column({ type: 'text' })
  reason: string;

  @Column({ name: 'signal_type', type: 'varchar', length: 100 })
  signalType: string;

  @Column({ name: 'signal_payload', type: 'jsonb', default: {} })
  signalPayload: Record<string, unknown>;

  @Column({ type: 'timestamptz', default: () => 'NOW()' })
  timestamp: Date;
}
