import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';

/**
 * We use a lightweight entity inline here since the location module
 * is self-contained. The entity maps to the incident_locations table.
 */
import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  Index,
} from 'typeorm';

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
}

export { IncidentLocation as IncidentLocationEntity };

export interface CreateLocationDto {
  latitude: number;
  longitude: number;
  accuracy?: number;
  speed?: number;
  heading?: number;
  altitude?: number;
  provider?: string;
  timestamp?: string;
}

@Injectable()
export class LocationService {
  private readonly logger = new Logger(LocationService.name);

  constructor(
    @InjectRepository(IncidentLocation)
    private readonly locationRepo: Repository<IncidentLocation>,
  ) {}

  /**
   * Record a new location update for an incident.
   * Also updates the incident's last_location fields.
   */
  async addLocation(
    incidentId: string,
    dto: CreateLocationDto,
  ): Promise<IncidentLocation> {
    const timestamp = dto.timestamp ? new Date(dto.timestamp) : new Date();

    const location = this.locationRepo.create({
      incidentId,
      latitude: dto.latitude,
      longitude: dto.longitude,
      accuracy: dto.accuracy ?? null,
      speed: dto.speed ?? null,
      heading: dto.heading ?? null,
      altitude: dto.altitude ?? null,
      provider: dto.provider ?? null,
      timestamp,
    });

    const saved = await this.locationRepo.save(location);

    // Update incident last_location fields
    await this.updateIncidentLastLocation(
      incidentId,
      dto.latitude,
      dto.longitude,
      timestamp,
    );

    // Create incident event
    await this.createIncidentEvent(incidentId, 'location_update', {
      locationId: saved.id,
      latitude: dto.latitude,
      longitude: dto.longitude,
      accuracy: dto.accuracy,
      speed: dto.speed,
    });

    this.logger.debug(
      `Location recorded for incident ${incidentId}: ` +
        `${dto.latitude},${dto.longitude} (accuracy: ${dto.accuracy ?? 'n/a'})`,
    );

    return saved;
  }

  /**
   * Get the full location trail for an incident.
   */
  async getLocationTrail(
    incidentId: string,
    options?: { limit?: number; since?: Date },
  ): Promise<IncidentLocation[]> {
    const qb = this.locationRepo
      .createQueryBuilder('loc')
      .where('loc.incident_id = :incidentId', { incidentId })
      .orderBy('loc.timestamp', 'ASC');

    if (options?.since) {
      qb.andWhere('loc.timestamp >= :since', { since: options.since });
    }

    if (options?.limit) {
      qb.limit(options.limit);
    }

    return qb.getMany();
  }

  /**
   * Get the latest location for an incident.
   */
  async getLatestLocation(
    incidentId: string,
  ): Promise<IncidentLocation | null> {
    return this.locationRepo.findOne({
      where: { incidentId },
      order: { timestamp: 'DESC' },
    });
  }

  // ------------------------------------------------------------------
  // Private helpers
  // ------------------------------------------------------------------

  private async updateIncidentLastLocation(
    incidentId: string,
    latitude: number,
    longitude: number,
    timestamp: Date,
  ): Promise<void> {
    try {
      await this.locationRepo.manager.query(
        `UPDATE incidents
         SET last_latitude = $1, last_longitude = $2, last_location_at = $3, updated_at = NOW()
         WHERE id = $4`,
        [latitude, longitude, timestamp, incidentId],
      );
    } catch (error) {
      this.logger.error(
        `Failed to update incident last location: ${error.message}`,
      );
    }
  }

  private async createIncidentEvent(
    incidentId: string,
    type: string,
    payload: Record<string, any>,
  ): Promise<void> {
    try {
      await this.locationRepo.manager.query(
        `INSERT INTO incident_events (incident_id, type, payload, source, is_internal)
         VALUES ($1, $2, $3, 'location_service', false)`,
        [incidentId, type, JSON.stringify(payload)],
      );
    } catch (error) {
      this.logger.error(
        `Failed to create incident event (${type}): ${error.message}`,
      );
    }
  }
}
