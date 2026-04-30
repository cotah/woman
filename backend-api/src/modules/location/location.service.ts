import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { IncidentLocation } from '../incidents/entities/incident-location.entity';
import { IncidentsService } from '../incidents/incidents.service';

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
    // IDOR fix B2 — needed to call assertOwnership before any operation
    private readonly incidentsService: IncidentsService,
  ) {}

  /**
   * Record a new location update for an incident.
   * Also updates the incident's last_location fields.
   */
  async addLocation(
    incidentId: string,
    userId: string,
    dto: CreateLocationDto,
  ): Promise<IncidentLocation> {
    // IDOR fix B2 — validate ownership before any operation
    await this.incidentsService.assertOwnership(incidentId, userId);

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
    userId: string,
    options?: { limit?: number; since?: Date },
  ): Promise<IncidentLocation[]> {
    // IDOR fix B2 — validate ownership before any operation
    await this.incidentsService.assertOwnership(incidentId, userId);

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
    payload: Record<string, unknown>,
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
