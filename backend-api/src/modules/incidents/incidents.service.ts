import {
  Injectable,
  Logger,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, In } from 'typeorm';
import {
  Incident,
  IncidentStatus,
  TriggerType,
  RiskLevel,
} from './entities/incident.entity';
import { IncidentEvent, IncidentEventType } from './entities/incident-event.entity';
import { IncidentLocation } from './entities/incident-location.entity';
import { CreateIncidentDto } from './dto/create-incident.dto';
import { ResolveIncidentDto, CancelIncidentDto, AddEventDto } from './dto/resolve-incident.dto';
import { RiskEngineService } from '../risk-engine/risk-engine.service';
import { RiskSignal, IncidentRiskState } from '../risk-engine/interfaces/risk-scoring-strategy';
import { NotificationsService, TrustedContactInfo } from '../notifications/notifications.service';
import { ContactsService } from '../contacts/contacts.service';
import { ContactAccessService } from '../contacts/contact-access.service';
import { UsersService } from '../users/users.service';

const DEFAULT_COUNTDOWN_SECONDS = 5;

export interface PaginatedResult<T> {
  data: T[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
}

export interface IncidentFilters {
  status?: IncidentStatus | IncidentStatus[];
  triggerType?: TriggerType;
  isTestMode?: boolean;
  from?: Date;
  to?: Date;
  page?: number;
  limit?: number;
}

@Injectable()
export class IncidentsService {
  private readonly logger = new Logger(IncidentsService.name);

  constructor(
    @InjectRepository(Incident)
    private readonly incidentRepo: Repository<Incident>,
    @InjectRepository(IncidentEvent)
    private readonly eventRepo: Repository<IncidentEvent>,
    @InjectRepository(IncidentLocation)
    private readonly locationRepo: Repository<IncidentLocation>,
    private readonly riskEngine: RiskEngineService,
    private readonly notificationsService: NotificationsService,
    private readonly contactsService: ContactsService,
    private readonly contactAccessService: ContactAccessService,
    private readonly usersService: UsersService,
  ) {}

  /**
   * Create a new incident from a trigger activation.
   *
   * Flow:
   * 1. Create incident in 'countdown' status
   * 2. Record initial location if provided
   * 3. Emit trigger_activated + countdown_started events
   * 4. Run risk engine for the trigger signal
   * 5. If coercion detected, silently escalate risk to critical
   */
  async create(
    userId: string,
    dto: CreateIncidentDto,
  ): Promise<Incident> {
    // Check for existing active incidents
    const activeIncident = await this.incidentRepo.findOne({
      where: {
        userId,
        status: In([
          IncidentStatus.PENDING,
          IncidentStatus.COUNTDOWN,
          IncidentStatus.ACTIVE,
          IncidentStatus.ESCALATED,
        ]),
      },
    });

    if (activeIncident) {
      throw new BadRequestException(
        'An active incident already exists. Resolve or cancel it before creating a new one.',
      );
    }

    const isCoercion = dto.isCoercion === true || dto.triggerType === TriggerType.COERCION_PIN;
    const countdownSeconds = dto.countdownSeconds ?? DEFAULT_COUNTDOWN_SECONDS;
    const now = new Date();
    const countdownEndsAt = new Date(now.getTime() + countdownSeconds * 1000);

    // Create the incident
    const incident = this.incidentRepo.create({
      userId,
      status: IncidentStatus.COUNTDOWN,
      triggerType: dto.triggerType,
      isCoercion,
      isTestMode: dto.isTestMode ?? false,
      currentRiskScore: 0,
      currentRiskLevel: RiskLevel.NONE,
      escalationWave: 0,
      startedAt: now,
      countdownEndsAt,
      lastLatitude: dto.location?.latitude ?? null,
      lastLongitude: dto.location?.longitude ?? null,
      lastLocationAt: dto.location ? now : null,
    });

    const saved = await this.incidentRepo.save(incident);
    this.logger.log(
      `Incident ${saved.id} created for user ${userId} ` +
        `(trigger=${dto.triggerType}, coercion=${isCoercion}, test=${saved.isTestMode})`,
    );

    // Save initial location
    if (dto.location) {
      const location = this.locationRepo.create({
        incidentId: saved.id,
        latitude: dto.location.latitude,
        longitude: dto.location.longitude,
        accuracy: dto.location.accuracy ?? null,
        speed: dto.location.speed ?? null,
        heading: dto.location.heading ?? null,
        altitude: dto.location.altitude ?? null,
        provider: dto.location.provider ?? null,
        timestamp: now,
      });
      await this.locationRepo.save(location);
    }

    // Emit trigger_activated event
    await this.appendEvent(saved.id, IncidentEventType.TRIGGER_ACTIVATED, {
      triggerType: dto.triggerType,
      isCoercion,
      isTestMode: saved.isTestMode,
      location: dto.location ?? null,
    });

    // Emit countdown_started event
    await this.appendEvent(saved.id, IncidentEventType.COUNTDOWN_STARTED, {
      countdownSeconds,
      countdownEndsAt: countdownEndsAt.toISOString(),
    });

    // Determine the initial signal type for risk scoring
    let signalType: string;
    if (isCoercion) {
      signalType = 'coercion_pin';
    } else if (dto.triggerType === TriggerType.PHYSICAL_BUTTON) {
      signalType = 'physical_trigger';
    } else {
      signalType = 'manual_panic_trigger';
    }

    // Run risk engine
    const riskState = this.buildRiskState(saved);
    const { result } = await this.riskEngine.evaluateAndPersist(
      { type: signalType, payload: { triggerType: dto.triggerType } },
      riskState,
    );

    // Update incident with new risk score
    saved.currentRiskScore = result.newScore;
    saved.currentRiskLevel = result.newLevel;

    // Coercion: silently escalate
    if (isCoercion) {
      await this.appendEvent(saved.id, IncidentEventType.COERCION_DETECTED, {
        note: 'Coercion PIN detected - silent escalation active',
      }, 'system', true);
    }

    // Emit risk change event
    if (result.scoreDelta > 0) {
      await this.appendEvent(saved.id, IncidentEventType.RISK_SCORE_CHANGED, {
        previousScore: result.previousScore,
        newScore: result.newScore,
        previousLevel: result.previousLevel,
        newLevel: result.newLevel,
        reasons: result.reasons,
      });
    }

    await this.incidentRepo.save(saved);
    return saved;
  }

  /**
   * Activate an incident after the countdown expires.
   * Called by a scheduled job or when the client confirms countdown completion.
   */
  async activate(incidentId: string, userId: string): Promise<Incident> {
    const incident = await this.findOneOrFail(incidentId, userId);

    if (incident.status !== IncidentStatus.COUNTDOWN) {
      throw new BadRequestException(
        `Cannot activate incident in status "${incident.status}". Must be in "countdown" status.`,
      );
    }

    const now = new Date();
    incident.status = IncidentStatus.ACTIVE;
    incident.activatedAt = now;

    // Run countdown_not_cancelled risk signal
    const riskState = this.buildRiskState(incident);
    const { result } = await this.riskEngine.evaluateAndPersist(
      { type: 'countdown_not_cancelled', payload: {} },
      riskState,
    );

    incident.currentRiskScore = result.newScore;
    incident.currentRiskLevel = result.newLevel;

    await this.appendEvent(incidentId, IncidentEventType.INCIDENT_ACTIVATED, {
      activatedAt: now.toISOString(),
      riskScore: result.newScore,
      riskLevel: result.newLevel,
    });

    if (result.scoreDelta > 0) {
      await this.appendEvent(incidentId, IncidentEventType.RISK_SCORE_CHANGED, {
        previousScore: result.previousScore,
        newScore: result.newScore,
        previousLevel: result.previousLevel,
        newLevel: result.newLevel,
        reasons: result.reasons,
      });
    }

    const saved = await this.incidentRepo.save(incident);
    this.logger.log(`Incident ${incidentId} activated (risk=${result.newScore}/${result.newLevel})`);

    // CRITICAL: Dispatch alert waves to trusted contacts
    await this.dispatchAlertsForIncident(saved, userId);

    return saved;
  }

  /**
   * Resolve an active incident (user confirmed safe).
   */
  async resolve(
    incidentId: string,
    userId: string,
    dto: ResolveIncidentDto,
  ): Promise<Incident> {
    const incident = await this.findOneOrFail(incidentId, userId);

    const resolvableStatuses = [
      IncidentStatus.COUNTDOWN,
      IncidentStatus.ACTIVE,
      IncidentStatus.ESCALATED,
    ];
    if (!resolvableStatuses.includes(incident.status)) {
      throw new BadRequestException(
        `Cannot resolve incident in status "${incident.status}".`,
      );
    }

    const now = new Date();
    incident.status = dto.isFalseAlarm
      ? IncidentStatus.FALSE_ALARM
      : IncidentStatus.RESOLVED;
    incident.resolvedAt = now;
    incident.resolutionReason = dto.reason ?? null;

    await this.appendEvent(incidentId, IncidentEventType.INCIDENT_RESOLVED, {
      resolvedAt: now.toISOString(),
      reason: dto.reason ?? null,
      isFalseAlarm: dto.isFalseAlarm ?? false,
      finalRiskScore: incident.currentRiskScore,
    });

    const saved = await this.incidentRepo.save(incident);
    this.logger.log(`Incident ${incidentId} resolved (${saved.status})`);

    // Cancel any pending alert waves
    await this.notificationsService.cancelPendingWaves(incidentId);

    return saved;
  }

  /**
   * Cancel an incident.
   *
   * Normal cancel: sets status to cancelled.
   * Secret cancel (coercion): UI appears cancelled but backend silently
   * escalates the incident to active+critical status.
   */
  async cancel(
    incidentId: string,
    userId: string,
    dto: CancelIncidentDto,
  ): Promise<Incident> {
    const incident = await this.findOneOrFail(incidentId, userId);

    const cancellableStatuses = [
      IncidentStatus.PENDING,
      IncidentStatus.COUNTDOWN,
      IncidentStatus.ACTIVE,
    ];
    if (!cancellableStatuses.includes(incident.status)) {
      throw new BadRequestException(
        `Cannot cancel incident in status "${incident.status}".`,
      );
    }

    const now = new Date();

    if (dto.isSecretCancel) {
      // SECRET CANCEL (coercion scenario):
      // The API response pretends the incident is cancelled,
      // but internally the incident is escalated to active/critical.
      incident.isCoercion = true;

      // Emit internal-only secret cancel event
      await this.appendEvent(
        incidentId,
        IncidentEventType.SECRET_CANCEL,
        {
          note: 'Secret cancel triggered - user is under duress. Escalating silently.',
          previousStatus: incident.status,
          timestamp: now.toISOString(),
        },
        'system',
        true, // internal only
      );

      // Escalate: set status to active (or escalated) with critical risk
      incident.status = IncidentStatus.ESCALATED;
      incident.activatedAt = incident.activatedAt ?? now;

      // Run coercion risk signal
      const riskState = this.buildRiskState(incident);
      const { result } = await this.riskEngine.evaluateAndPersist(
        { type: 'coercion_pin', payload: { secretCancel: true } },
        riskState,
      );

      incident.currentRiskScore = Math.max(result.newScore, 95);
      incident.currentRiskLevel = RiskLevel.CRITICAL;

      await this.appendEvent(
        incidentId,
        IncidentEventType.COERCION_DETECTED,
        {
          note: 'Coercion detected via secret cancel',
          riskScore: incident.currentRiskScore,
        },
        'system',
        true,
      );

      const saved = await this.incidentRepo.save(incident);
      this.logger.warn(
        `Incident ${incidentId} SECRET CANCEL - escalated to critical (score=${incident.currentRiskScore})`,
      );

      // CRITICAL: Dispatch emergency alerts silently — user is under duress
      await this.dispatchAlertsForIncident(saved, userId);

      // Return a response that looks like a normal cancellation to the client
      return {
        ...saved,
        status: IncidentStatus.CANCELLED,
        resolvedAt: now,
        currentRiskScore: 0,
        currentRiskLevel: RiskLevel.NONE,
      } as Incident;
    }

    // Normal cancel
    incident.status = IncidentStatus.CANCELLED;
    incident.resolvedAt = now;
    incident.resolutionReason = dto.reason ?? 'User cancelled';

    await this.appendEvent(incidentId, IncidentEventType.COUNTDOWN_CANCELLED, {
      cancelledAt: now.toISOString(),
      reason: dto.reason ?? 'User cancelled',
    });

    const saved = await this.incidentRepo.save(incident);
    this.logger.log(`Incident ${incidentId} cancelled`);

    // Cancel any pending alert waves
    await this.notificationsService.cancelPendingWaves(incidentId);

    return saved;
  }

  /**
   * Process an incoming risk signal for an active incident.
   */
  async processRiskSignal(
    incidentId: string,
    userId: string,
    signal: RiskSignal,
  ): Promise<Incident> {
    const incident = await this.findOneOrFail(incidentId, userId);

    const activeStatuses = [
      IncidentStatus.ACTIVE,
      IncidentStatus.ESCALATED,
      IncidentStatus.COUNTDOWN,
    ];
    if (!activeStatuses.includes(incident.status)) {
      throw new BadRequestException(
        `Cannot process signals for incident in status "${incident.status}".`,
      );
    }

    const riskState = this.buildRiskState(incident);
    const { result } = await this.riskEngine.evaluateAndPersist(signal, riskState);

    if (result.scoreDelta > 0) {
      incident.currentRiskScore = result.newScore;
      incident.currentRiskLevel = result.newLevel;

      await this.appendEvent(incidentId, IncidentEventType.RISK_SCORE_CHANGED, {
        previousScore: result.previousScore,
        newScore: result.newScore,
        previousLevel: result.previousLevel,
        newLevel: result.newLevel,
        signal: signal.type,
        reasons: result.reasons,
      });

      // Auto-escalate status if risk reaches critical
      if (
        result.newLevel === RiskLevel.CRITICAL &&
        incident.status === IncidentStatus.ACTIVE
      ) {
        incident.status = IncidentStatus.ESCALATED;
        await this.appendEvent(incidentId, IncidentEventType.ESCALATION_WAVE, {
          wave: incident.escalationWave + 1,
          reason: 'Risk score reached critical threshold',
        });
        incident.escalationWave += 1;
      }

      await this.incidentRepo.save(incident);
    }

    return incident;
  }

  /**
   * Add a custom event to an incident's timeline.
   */
  async addEvent(
    incidentId: string,
    userId: string,
    dto: AddEventDto,
  ): Promise<IncidentEvent> {
    const incident = await this.findOneOrFail(incidentId, userId);

    // Validate event type
    const eventType = dto.type as IncidentEventType;
    if (!Object.values(IncidentEventType).includes(eventType)) {
      throw new BadRequestException(`Invalid event type: "${dto.type}"`);
    }

    return this.appendEvent(
      incidentId,
      eventType,
      dto.payload ?? {},
      dto.source ?? 'client',
    );
  }

  /**
   * Get a single incident by ID, verifying ownership.
   */
  async findOne(incidentId: string, userId: string): Promise<Incident> {
    return this.findOneOrFail(incidentId, userId);
  }

  /**
   * List incidents with pagination and filters.
   */
  async findAll(
    userId: string,
    filters: IncidentFilters = {},
  ): Promise<PaginatedResult<Incident>> {
    const page = Math.max(filters.page ?? 1, 1);
    const limit = Math.min(Math.max(filters.limit ?? 20, 1), 100);
    const offset = (page - 1) * limit;

    const qb = this.incidentRepo
      .createQueryBuilder('incident')
      .where('incident.user_id = :userId', { userId })
      .orderBy('incident.created_at', 'DESC')
      .skip(offset)
      .take(limit);

    if (filters.status) {
      if (Array.isArray(filters.status)) {
        qb.andWhere('incident.status IN (:...statuses)', {
          statuses: filters.status,
        });
      } else {
        qb.andWhere('incident.status = :status', { status: filters.status });
      }
    }

    if (filters.triggerType) {
      qb.andWhere('incident.trigger_type = :triggerType', {
        triggerType: filters.triggerType,
      });
    }

    if (filters.isTestMode !== undefined) {
      qb.andWhere('incident.is_test_mode = :isTestMode', {
        isTestMode: filters.isTestMode,
      });
    }

    if (filters.from) {
      qb.andWhere('incident.created_at >= :from', { from: filters.from });
    }

    if (filters.to) {
      qb.andWhere('incident.created_at <= :to', { to: filters.to });
    }

    const [data, total] = await qb.getManyAndCount();
    const totalPages = Math.ceil(total / limit);

    return { data, total, page, limit, totalPages };
  }

  /**
   * Get events for an incident.
   */
  async getEvents(
    incidentId: string,
    userId: string,
    includeInternal = false,
  ): Promise<IncidentEvent[]> {
    await this.findOneOrFail(incidentId, userId);

    const qb = this.eventRepo
      .createQueryBuilder('event')
      .where('event.incident_id = :incidentId', { incidentId })
      .orderBy('event.timestamp', 'ASC');

    if (!includeInternal) {
      qb.andWhere('event.is_internal = false');
    }

    return qb.getMany();
  }

  /**
   * Asserts that the given incident exists and belongs to the user.
   * Throws NotFoundException if either condition fails.
   *
   * Used by external services (audio, location) to enforce ownership
   * before any operation on an incident's nested resources.
   *
   * IDOR fix B2 — validate ownership from outside IncidentsService.
   */
  async assertOwnership(incidentId: string, userId: string): Promise<void> {
    await this.findOneOrFail(incidentId, userId);
  }

  // ─── Private helpers ──────────────────────────────────────────

  private async findOneOrFail(
    incidentId: string,
    userId: string,
  ): Promise<Incident> {
    const incident = await this.incidentRepo.findOne({
      where: { id: incidentId },
    });

    // security: unified to 404 to prevent existence leak (B2)
    // A 403 distinct from 404 lets an attacker enumerate UUIDs
    // (different status confirms the incident exists). For an
    // app handling domestic-violence incidents, that is unacceptable.
    if (!incident || incident.userId !== userId) {
      throw new NotFoundException(`Incident ${incidentId} not found`);
    }

    return incident;
  }

  private async appendEvent(
    incidentId: string,
    type: IncidentEventType,
    payload: Record<string, any> = {},
    source = 'system',
    isInternal = false,
  ): Promise<IncidentEvent> {
    const event = this.eventRepo.create({
      incidentId,
      type,
      payload,
      source,
      isInternal,
      timestamp: new Date(),
    });
    return this.eventRepo.save(event);
  }

  private buildRiskState(incident: Incident): IncidentRiskState {
    return {
      incidentId: incident.id,
      currentScore: incident.currentRiskScore,
      currentLevel: incident.currentRiskLevel,
      isCoercion: incident.isCoercion,
      isTestMode: incident.isTestMode,
      triggerType: incident.triggerType,
      eventCount: 0,
    };
  }

  /**
   * Fetch trusted contacts, generate access tokens, and dispatch alert waves.
   * Called when an incident is activated or during coercion escalation.
   */
  private async dispatchAlertsForIncident(
    incident: Incident,
    userId: string,
  ): Promise<void> {
    try {
      // Fetch user info for the alert message
      const user = await this.usersService.findById(userId);
      if (!user) {
        this.logger.error(
          `Cannot dispatch alerts for incident ${incident.id}: user ${userId} not found`,
        );
        return;
      }

      const userName = `${user.firstName} ${user.lastName}`.trim() || user.email;

      // Fetch all trusted contacts for this user
      const contacts = await this.contactsService.findAllByUser(userId);
      if (contacts.length === 0) {
        this.logger.warn(
          `No trusted contacts configured for user ${userId}. No alerts will be dispatched for incident ${incident.id}.`,
        );
        return;
      }

      // Generate access tokens and build TrustedContactInfo array
      const contactInfos: TrustedContactInfo[] = [];

      for (const contact of contacts) {
        let accessUrl: string | undefined;
        try {
          const tokenResult = await this.contactAccessService.generateToken(
            incident.id,
            contact.id,
          );
          accessUrl = tokenResult.accessUrl;
        } catch (error) {
          this.logger.warn(
            `Failed to generate access token for contact ${contact.id}: ${error.message}`,
          );
        }

        contactInfos.push({
          id: contact.id,
          name: contact.name,
          phone: contact.phone,
          email: contact.email ?? undefined,
          priority: contact.priority,
          locale: contact.locale || 'en',
          canReceiveSms: contact.canReceiveSms,
          canReceivePush: contact.canReceivePush,
          canReceiveVoiceCall: contact.canReceiveVoiceCall,
          accessUrl,
          lastLatitude: incident.lastLatitude ? Number(incident.lastLatitude) : undefined,
          lastLongitude: incident.lastLongitude ? Number(incident.lastLongitude) : undefined,
        });
      }

      // Dispatch the alert waves
      await this.notificationsService.dispatchAlertWaves(
        incident.id,
        userId,
        userName,
        contactInfos,
        undefined, // use default wave config
        incident.isTestMode,
      );

      this.logger.log(
        `Alert waves dispatched for incident ${incident.id} to ${contactInfos.length} contacts`,
      );
    } catch (error) {
      // Alert dispatch failure must NOT prevent the incident from being active.
      // Log the error but don't throw — the incident is already saved.
      this.logger.error(
        `Failed to dispatch alerts for incident ${incident.id}: ${error.message}`,
        error.stack,
      );
    }
  }
}
