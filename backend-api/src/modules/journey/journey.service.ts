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
import { NotificationsService, TrustedContactInfo } from '../notifications/notifications.service';
import { ContactsService } from '../contacts/contacts.service';
import { UsersService } from '../users/users.service';
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
    private readonly notificationsService: NotificationsService,
    private readonly contactsService: ContactsService,
    private readonly usersService: UsersService,
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

    // AI estimate: calculate average duration for similar routes
    const aiEstimate = await this.estimateDuration(userId, dto.destLatitude, dto.destLongitude);
    journey.aiEstimatedMinutes = aiEstimate;

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

    // If AI has an estimate and user set time is much less, schedule a smart check-in
    if (aiEstimate && dto.durationMinutes < aiEstimate) {
      const checkinDelayMs = dto.durationMinutes * 60 * 1000;
      await this.expiryQueue.add(
        'smart-checkin',
        { journeyId: saved.id },
        {
          delay: Math.max(checkinDelayMs, 0),
          jobId: `journey-checkin-${saved.id}`,
          removeOnComplete: true,
          removeOnFail: false,
        },
      );
    }

    this.logger.log(
      `Journey ${saved.id} created for user ${userId} ` +
        `(duration=${dto.durationMinutes}min, aiEstimate=${aiEstimate ?? 'none'}, expires=${expiresAt.toISOString()})`,
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
   * Instead of immediately escalating, sends a safety check-in push first.
   * If the user doesn't respond within 5 minutes, then escalates.
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

    // If check-in was already sent and user responded 'help', escalate now
    if (journey.checkinSent && journey.checkinResponse === 'help') {
      await this.escalateJourney(journey);
      return;
    }

    // If check-in was already sent but no response after grace period, escalate
    if (journey.checkinSent && !journey.checkinResponse) {
      this.logger.warn(`Journey ${journeyId} expired — no check-in response, escalating`);
      await this.escalateJourney(journey);
      return;
    }

    // If check-in response is 'ok', the user already extended — skip
    if (journey.checkinSent && journey.checkinResponse === 'ok') {
      this.logger.log(`Journey ${journeyId} check-in was ok, skipping escalation`);
      return;
    }

    // First expiry: send safety check-in instead of immediate escalation
    journey.checkinSent = true;
    journey.checkinSentAt = new Date();
    await this.journeyRepo.save(journey);

    this.logger.log(`Journey ${journeyId} expired — sending safety check-in push`);

    // Send push notification asking "Are you okay?"
    try {
      await this.notificationsService.sendSafetyCheckin(
        journey.userId,
        journeyId,
      );
    } catch (error) {
      this.logger.warn(`Failed to send check-in push for journey ${journeyId}: ${error.message}`);
    }

    // Schedule final escalation in 5 minutes if no response
    await this.expiryQueue.add(
      'expire',
      { journeyId },
      {
        delay: 5 * 60 * 1000, // 5 minutes grace period
        jobId: `journey-escalation-${journeyId}`,
        removeOnComplete: true,
        removeOnFail: false,
      },
    );
  }

  /**
   * Handle user's response to the safety check-in push.
   * 'ok' = user is fine, extend journey by 30 minutes
   * 'help' = user needs help, escalate immediately
   */
  async respondToCheckin(
    journeyId: string,
    userId: string,
    response: 'ok' | 'help',
  ): Promise<Journey> {
    const journey = await this.findOneOrFail(journeyId, userId);

    if (journey.status !== JourneyStatus.ACTIVE) {
      throw new BadRequestException(
        `Cannot respond to check-in for journey in status "${journey.status}".`,
      );
    }

    journey.checkinResponse = response;
    await this.journeyRepo.save(journey);

    if (response === 'ok') {
      // User is fine — extend journey by 30 minutes
      const newExpiresAt = new Date(Date.now() + 30 * 60 * 1000);
      journey.expiresAt = newExpiresAt;
      journey.durationMinutes += 30;
      journey.checkinSent = false;
      journey.checkinResponse = null;
      journey.checkinSentAt = null;
      await this.journeyRepo.save(journey);

      // Remove pending escalation and schedule new expiry
      await this.removeExpiryJob(journeyId);
      try {
        const escalationJob = await this.expiryQueue.getJob(`journey-escalation-${journeyId}`);
        if (escalationJob) await escalationJob.remove();
      } catch (_) {}

      await this.expiryQueue.add(
        'expire',
        { journeyId },
        {
          delay: 30 * 60 * 1000,
          jobId: `journey-expiry-${journeyId}`,
          removeOnComplete: true,
          removeOnFail: false,
        },
      );

      this.logger.log(`Journey ${journeyId} check-in OK — extended 30min`);
    } else {
      // User needs help — escalate now
      this.logger.warn(`Journey ${journeyId} check-in HELP — escalating immediately`);
      await this.escalateJourney(journey);
    }

    return journey;
  }

  /**
   * Smart check-in: called by queue when AI thinks the user might be
   * taking longer than usual (even before the timer expires).
   */
  async smartCheckin(journeyId: string): Promise<void> {
    const journey = await this.journeyRepo.findOne({
      where: { id: journeyId },
    });

    if (!journey || journey.status !== JourneyStatus.ACTIVE) return;
    if (journey.checkinSent) return; // Already sent

    this.logger.log(`Journey ${journeyId} — AI smart check-in triggered`);

    try {
      await this.notificationsService.sendSafetyCheckin(
        journey.userId,
        journeyId,
      );
      journey.checkinSent = true;
      journey.checkinSentAt = new Date();
      await this.journeyRepo.save(journey);
    } catch (error) {
      this.logger.warn(`Failed to send smart check-in for journey ${journeyId}: ${error.message}`);
    }
  }

  /**
   * Estimate journey duration based on user's past completed journeys
   * to similar destinations (within 500m radius).
   */
  private async estimateDuration(
    userId: string,
    destLat: number,
    destLng: number,
  ): Promise<number | null> {
    // Get completed journeys for this user
    const pastJourneys = await this.journeyRepo.find({
      where: { userId, status: JourneyStatus.COMPLETED },
      order: { completedAt: 'DESC' },
      take: 50,
    });

    if (pastJourneys.length === 0) return null;

    // Filter to journeys with similar destinations (within 500m)
    const similarJourneys = pastJourneys.filter((j) => {
      const dist = this.haversineDistance(
        destLat,
        destLng,
        Number(j.destLatitude),
        Number(j.destLongitude),
      );
      return dist <= 500;
    });

    if (similarJourneys.length < 2) return null;

    // Calculate average actual duration (startedAt to completedAt)
    const durations = similarJourneys
      .filter((j) => j.completedAt && j.startedAt)
      .map((j) => {
        return (j.completedAt.getTime() - j.startedAt.getTime()) / (60 * 1000);
      });

    if (durations.length === 0) return null;

    const avgDuration = durations.reduce((a, b) => a + b, 0) / durations.length;

    // Add 20% buffer
    return Math.round(avgDuration * 1.2);
  }

  /**
   * Escalate a journey to an incident.
   */
  private async escalateJourney(journey: Journey): Promise<void> {
    journey.status = JourneyStatus.EXPIRED;
    await this.journeyRepo.save(journey);

    this.logger.warn(`Journey ${journey.id} expired for user ${journey.userId}`);

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
          `Journey ${journey.id} escalated to incident ${incident.id}`,
        );
      } catch (error) {
        this.logger.error(
          `Failed to escalate journey ${journey.id}: ${error.message}`,
          error.stack,
        );
      }
    } else {
      this.logger.log(
        `Journey ${journey.id} is in test mode, skipping incident escalation`,
      );
    }
  }

  // ─── Private helpers ──────────────────────────────────────────

  private async completeJourney(journey: Journey): Promise<void> {
    journey.status = JourneyStatus.COMPLETED;
    journey.completedAt = new Date();
    await this.journeyRepo.save(journey);
    await this.removeExpiryJob(journey.id);

    // Also remove escalation job if exists
    try {
      const escJob = await this.expiryQueue.getJob(`journey-escalation-${journey.id}`);
      if (escJob) await escJob.remove();
    } catch (_) {}

    // Notify trusted contacts: "User arrived safely"
    try {
      const user = await this.usersService.findById(journey.userId);
      if (!user) return;

      const userName = `${user.firstName} ${user.lastName}`.trim() || user.email;
      const contacts = await this.contactsService.findAllByUser(journey.userId);

      if (contacts.length > 0) {
        const contactInfos: TrustedContactInfo[] = contacts.map((c) => ({
          id: c.id,
          name: c.name,
          phone: c.phone ?? undefined,
          email: c.email ?? undefined,
          priority: c.priority ?? 1,
          locale: c.locale || 'en',
          canReceiveSms: !!c.phone,
          canReceivePush: true,
          canReceiveVoiceCall: !!c.phone,
        }));

        await this.notificationsService.sendArrivalNotification(
          journey.userId,
          userName,
          contactInfos,
          journey.destLabel ?? undefined,
        );

        this.logger.log(
          `Arrival notification sent to ${contacts.length} contacts for journey ${journey.id}`,
        );
      }
    } catch (error) {
      // Non-fatal: journey is already completed, notification is best-effort
      this.logger.warn(
        `Failed to send arrival notification for journey ${journey.id}: ${error.message}`,
      );
    }
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
