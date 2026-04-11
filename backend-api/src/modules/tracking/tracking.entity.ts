import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  Index,
} from 'typeorm';

/**
 * Stores continuous location snapshots for the always-on tracking feature.
 * Separate from incident_locations which are tied to active emergencies.
 *
 * This data is used by the AI to learn the user's frequent places,
 * detect anomalies, and prompt safety checks at unknown locations.
 */
@Entity('location_snapshots')
@Index(['userId', 'timestamp'])
@Index(['userId', 'latitude', 'longitude'])
export class LocationSnapshot {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'user_id', type: 'uuid' })
  @Index()
  userId: string;

  @Column({ type: 'double precision' })
  latitude: number;

  @Column({ type: 'double precision' })
  longitude: number;

  @Column({ type: 'double precision', nullable: true })
  accuracy: number;

  @Column({ type: 'timestamptz', default: () => 'NOW()' })
  timestamp: Date;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt: Date;
}

/**
 * Stores learned places — locations the user frequently visits.
 * The AI identifies these from location_snapshots clustering.
 */
@Entity('learned_places')
@Index(['userId'])
export class LearnedPlace {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'user_id', type: 'uuid' })
  @Index()
  userId: string;

  @Column({ type: 'double precision' })
  latitude: number;

  @Column({ type: 'double precision' })
  longitude: number;

  @Column({ type: 'varchar', length: 100, nullable: true })
  label: string;

  @Column({ name: 'auto_label', type: 'varchar', length: 50, nullable: true })
  autoLabel: string;

  @Column({ name: 'visit_count', type: 'int', default: 0 })
  visitCount: number;

  @Column({ name: 'is_confirmed_safe', type: 'boolean', default: false })
  isConfirmedSafe: boolean;

  @Column({ name: 'is_flagged', type: 'boolean', default: false })
  isFlagged: boolean;

  @Column({ name: 'flag_reason', type: 'text', nullable: true })
  flagReason: string;

  @Column({ name: 'first_visited', type: 'timestamptz' })
  firstVisited: Date;

  @Column({ name: 'last_visited', type: 'timestamptz' })
  lastVisited: Date;

  @Column({ name: 'hour_distribution', type: 'jsonb', nullable: true })
  hourDistribution: Record<string, number>;

  @Column({ name: 'weekday_distribution', type: 'jsonb', nullable: true })
  weekdayDistribution: Record<string, number>;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt: Date;
}
