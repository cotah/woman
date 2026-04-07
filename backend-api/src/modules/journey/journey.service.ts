import {
  Injectable,
  Logger,
  NotFoundException,
  ForbiddenException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';
import { Journey, JourneyStatus } from './entities/journey.entity';
import { CreateJourneyDto, ExtendJourneyDto, JourneyLocationDto } from './dto/create-journey.dto';
import { IncidentsService } from '../incidents/incidents.service';
import { TriggerType } from '../incidents/entities/incident.entity';

@Injectable()
export class JourneyService {
  private readonly logger = new Logger(JourneyService.name);

  constructor(
    @InjectRepository(Journey)
    private readonly journeyRepo: Repository<Journey>,
    @InjectQueue('journey-expiry')
    private readonly expiryQueue: Queue,
    private readonly incidentsService: IncidentsService,
  ) {}

  /**
   * Create a new Safe Journey. Schedules a delayed BullMQ job
   * that will fire when the journey expires (user hasn't arrived).
   */
  async create(userId: string, dto: CreateJourneyDto): Promise<Journey> {
    // Check for existing active journey
    const existing = await this.journeyRepo.findOne({
      where: { userId, status: JourneyStatus.ACTIVE },
    });

    if (existing) {
      throw new BadRequestException(
        'An active journey already exists. Complete or cancel it before starting a new one.',
      );
    }

    const now = new Date();
    const expiresAt = new Date(now.getTime() + dto.durationMinutes * 60 * 1000);

    const journey = this.journeyRepo.create({
      userId,
      status: JourneyStatus.ACTIVE,
      startLatitude: dto.startLatitude ?? null,
      startLongitude: dto.startLongitude ?? null,
      destLatitude: dto.destLatitude,
      destLongitude: dto.destLongitude,
      destLabel: dto.destLabel ?? null,
      arrivalRadiusMeters: dto.arrivalRadiusMeters ?? 200,
      durationMinutes: dto.durationMinutes,
      expiresAt,
      startedAt: now,
      isTestMode: dto.isTestMode ?? false,
    } as Partial<Journey>);

    const saved = await this.journeyRepo.save(journey);

    // Schedule expiry job
    const delayMs = expiresAt.getTime() - Date.now();
    await this.expiryQueue.add(
      'expire',
      { journeyId: saved.id },
      {
        delay: Math.max(delayMs, 0),
        jobId: `journey-expiry-${saved.id}`,
        removeOnComplete: true,
        removeOnFail: false,
      },
    );

    this.logger.log(
      `Journey ${saved.id} created for user ${userId} ` +
        `(duration=${dto.durationMinutes}min, expires=${expiresAt.toISOString()})`,
    );

    return saved;
  }

  /**
   * Get the current active journey for a user, or null if none.
   */
  async getActive(userId: string): Promise<Journey | null> {
    return this.journeyRepo.findOne({
      where: { userId, status: JourneyStatus.ACTIVE },
    });
  }

  /**
   * Find a journey by ID, verifying ownership.
   */
  async findOneOrFail(journeyId: string, userId: string): Promise<Journey> {
    const journey = await this.journeyRepo.findOne({
      where: { id: journeyId },
    });

    if (!journey) {
      throw new NotFoundException(`Journey ${journeyId} not found`);
    }

    if (journey.userId !== userId) {
      throw new ForbiddenException('You do not have access to this journey');
    }

    return journey;
  }

  /**
   * Check if the user has arrived at the destination.
   * Uses Haversine formula to compute distance between current location
   * and the destination. Auto-completes the journey if within radius.
   */
  async checkArrival(
    journeyId: string,
    userId: string,
    dto: JourneyLocationDto,
  ): Promise<{ arrived: boolean; distanceMeters: number; journey: Journey }> {
    const journey = await this.findOneOrFail(journeyId, userId);

    if (journey.status !== JourneyStatus.ACTIVE) {
      throw new BadRequestException(
        `Cannot check arrival for journey in status "${journey.status}".`,
      );
    }

    // Update last checkin
    journey.lastCheckinAt = new Date();
    await this.journeyRepo.save(journey);

    // Haversine distance calculation
    const distanceMeters = this.haversineDistance(
      dto.latitude,
      dto.longitude,
      Number(journey.destLatitude),
      Number(journey.destLongitude),
    );

    const arrived = distanceMeters <= journey.arrivalRadiusMeters;

    if (arrived) {
      await this.completeJourney(journey);
      this.logger.log(
        `Journey ${journeyId} auto-completed: user arrived within ${distanceMeters.toFixed(0)}m (radius=${journey.arrivalRadiusMeters}m)`,
      );
    }

    return {
      arrived,
      distanceMeters: Math.round(distanceMeters),
      journey,
    };
  }

  /**
   * Extend the journey duration (check-in). Removes the old expiry
   * job and schedules a new one with the extended time.
   */
  async checkin(
    journeyId: string,
    userId: string,
    dto: ExtendJourneyDto,
  ): Promise<Journey> {
    const journey = await this.findOneOrFail(journeyId, userId);

    if (journey.status !== JourneyStatus.ACTIVE) {
      throw new BadRequestException(
        `Cannot extend journey in status "${journey.status}".`,
      );
    }

    const now = new Date();
    const newExpiresAt = new Date(
      journey.expiresAt.getTime() + dto.additionalMinutes * 60 * 1000,
    );

    journey.expiresAt = newExpiresAt;
    journey.durationMinutes += dto.additionalMinutes;
    journey.lastCheckinAt = now;

    const saved = await this.journeyRepo.save(journey);

    // Remove old expiry job and schedule new one
    await this.removeExpiryJob(journeyId);

    const delayMs = newExpiresAt.getTime() - Date.now();
    await this.expiryQueue.add(
      'expire',
      { journeyId: saved.id },
      {
        delay: Math.max(delayMs, 0),
        jobId: `journey-expiry-${saved.id}`,
        removeOnComplete: true,
        removeOnFail: false,
      },
    );

    this.logger.log(
      `Journey ${journeyId} extended by ${dto.additionalMinutes}min, new expires=${newExpiresAt.toISOString()}`,
    );

    return saved;
  }

  /**
   * Manually complete a journey (user confirms arrival).
   */
  async complete(journeyId: string, userId: string): Promise<Journey> {
    const journey = await this.findOneOrFail(journeyId, userId);

    if (journey.status !== JourneyStatus.ACTIVE) {
      throw new BadRequestException(
        `Cannot complete journey in status "${journey.status}".`,
      );
    }

    await this.completeJourney(journey);

    this.logger.log(`Journey ${journeyId} manually completed by user ${userId}`);
    return journey;
  }

  /**
   * Cancel an active journey.
   */
  async cancel(journeyId: string, userId: string): Promise<Journey> {
    const journey = await this.findOneOrFail(journeyId, userId);

    if (journey.status !== JourneyStatus.ACTIVE) {
      throw new BadRequestException(
        `Cannot cancel journey in status "${journey.status}".`,
      );
    }

    journey.status = JourneyStatus.CANCELLED;
    const saved = await this.journeyRepo.save(journey);

    await this.removeExpiryJob(journeyId);

    this.logger.log(`Journey ${journeyId} cancelled by user ${userId}`);
    return saved;
  }

  /**
   * Called by the queue processor when a journey expires.
   * If the journey is still active, mark it expired and escalate
   * to an incident (unless in test mode).
   */
  async expire(journeyId: string): Promise<void> {
    const journey = await this.journeyRepo.findOne({
      where: { id: journeyId },
    });

    if (!journey) {
      this.logger.warn(`Journey ${journeyId} not found during expiry`);
      return;
    }

    if (journey.status !== JourneyStatus.ACTIVE) {
      this.logger.log(
        `Journey ${journeyId} is ${journey.status}, skipping expiry`,
      );
      return;
    }

    journey.status = JourneyStatus.EXPIRED;
    await this.journeyRepo.save(journey);

    this.logger.warn(`Journey ${journeyId} expired for user ${journey.userId}`);

    if (!journey.isTestMode) {
      try {
        const incident = await this.incidentsService.create(journey.userId, {
          triggerType: TriggerType.GEOFENCE,
          isTestMode: false,
          location: journey.startLatitude
            ? {
                latitude: Number(journey.startLatitude),
                longitude: Number(journey.startLongitude),
              }
            : undefined,
        });

        journey.status = JourneyStatus.ESCALATED;
        journey.incidentId = incident.id;
        await this.journeyRepo.save(journey);

        this.logger.warn(
          `Journey ${journeyId} escalated to incident ${incident.id}`,
        );
      } catch (error) {
        this.logger.error(
          `Failed to escalate journey ${journeyId}: ${error.message}`,
          error.stack,
        );
      }
    } else {
      this.logger.log(
        `Journey ${journeyId} is in test mode, skipping incident escalation`,
      );
    }
  }

  // ─── Private helpers ──────────────────────────────────────────

  private async completeJourney(journey: Journey): Promise<void> {
    journey.status = JourneyStatus.COMPLETED;
    journey.completedAt = new Date();
    await this.journeyRepo.save(journey);
    await this.removeExpiryJob(journey.id);
  }

  private async removeExpiryJob(journeyId: string): Promise<void> {
    try {
      const job = await this.expiryQueue.getJob(`journey-expiry-${journeyId}`);
      if (job) {
        await job.remove();
      }
    } catch (error) {
      this.logger.warn(
        `Could not remove expiry job for journey ${journeyId}: ${error.message}`,
      );
    }
  }

  /**
   * Haversine formula — returns distance in meters between two lat/lng points.
   */
  private haversineDistance(
    lat1: number,
    lng1: number,
    lat2: number,
    lng2: number,
  ): number {
    const R = 6371000; // Earth radius in meters
    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLng = ((lng2 - lng1) * Math.PI) / 180;
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos((lat1 * Math.PI) / 180) *
        Math.cos((lat2 * Math.PI) / 180) *
        Math.sin(dLng / 2) *
        Math.sin(dLng / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }
}
