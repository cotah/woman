import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  ManyToOne,
  JoinColumn,
  Index,
} from 'typeorm';
import { Incident } from './incident.entity';

@Entity('incident_locations')
@Index('idx_incident_locations_incident', ['incidentId', 'timestamp'])
export class IncidentLocation {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'incident_id', type: 'uuid' })
  incidentId: string;

  @Column({ type: 'double precision' })
  latitude: number;

  @Column({ type: 'double precision' })
  longitude: number;

  @Column({ type: 'double precision', nullable: true })
  accuracy: number | null;

  @Column({ type: 'double precision', nullable: true })
  speed: number | null;

  @Column({ type: 'double precision', nullable: true })
  heading: number | null;

  @Column({ type: 'double precision', nullable: true })
  altitude: number | null;

  @Column({ type: 'varchar', length: 50, nullable: true })
  provider: string | null;

  @Column({ type: 'timestamptz', default: () => 'NOW()' })
  timestamp: Date;

  // Relations
  @ManyToOne(() => Incident, (incident) => incident.locations)
  @JoinColumn({ name: 'incident_id' })
  incident: Incident;
}
