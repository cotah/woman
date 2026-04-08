import {
  Controller,
  Get,
  Post,
  Param,
  Body,
  Headers,
  ParseUUIDPipe,
  HttpCode,
  HttpStatus,
  UnauthorizedException,
  NotFoundException,
  SetMetadata,
  Logger,
  Inject,
  forwardRef,
} from '@nestjs/common';
import { ApiTags, ApiOperation, ApiResponse } from '@nestjs/swagger';
import { SkipThrottle } from '@nestjs/throttler';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { ContactAccessService, ValidatedTokenData } from './contact-access.service';
import { IS_PUBLIC_KEY } from '../auth/guards/jwt-auth.guard';
import { Incident } from '../incidents/entities/incident.entity';
import { IncidentEvent } from '../incidents/entities/incident-event.entity';
import { IncidentLocation } from '../incidents/entities/incident-location.entity';
import { TrustedContact } from './entities/trusted-contact.entity';
import { User } from '../users/entities/user.entity';
import { NotificationsService } from '../notifications/notifications.service';
import { ContactRespondDto } from '../notifications/dto/contact-respond.dto';

const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

/**
 * Public-facing controller for the Contact Web Portal.
 *
 * Trusted contacts access this via a secure URL with a time-limited token.
 * All endpoints are @Public() (no JWT required) and authenticated via
 * Bearer token in the Authorization header.
 *
 * Routes:
 *   GET  /api/v1/contact/validate         — Validate the access token
 *   GET  /api/v1/contact/incident          — Get incident data for the contact
 *   POST /api/v1/contact/incident/:id/respond — Submit a contact response
 */
@ApiTags('Contact Portal')
@SkipThrottle() // Safety-critical: contact responses during emergencies must never be blocked
@Controller('contact')
export class ContactPortalController {
  private readonly logger = new Logger(ContactPortalController.name);

  constructor(
    private readonly contactAccessService: ContactAccessService,
    @Inject(forwardRef(() => NotificationsService))
    private readonly notificationsService: NotificationsService,
    @InjectRepository(Incident)
    private readonly incidentRepo: Repository<Incident>,
    @InjectRepository(IncidentEvent)
    private readonly eventRepo: Repository<IncidentEvent>,
    @InjectRepository(IncidentLocation)
    private readonly locationRepo: Repository<IncidentLocation>,
    @InjectRepository(TrustedContact)
    private readonly contactRepo: Repository<TrustedContact>,
    @InjectRepository(User)
    private readonly userRepo: Repository<User>,
  ) {}

  // ─── Token validation ─────────────────────────────────────────

  @Get('validate')
  @Public()
  @ApiOperation({ summary: 'Validate a contact access token' })
  @ApiResponse({ status: 200, description: 'Token is valid' })
  @ApiResponse({ status: 401, description: 'Invalid or expired token' })
  async validateToken(
    @Headers('authorization') authHeader: string,
  ) {
    const tokenData = await this.extractAndValidateToken(authHeader);
    return { valid: true, incidentId: tokenData.incidentId };
  }

  // ─── Incident data ────────────────────────────────────────────

  @Get('incident')
  @Public()
  @ApiOperation({ summary: 'Get incident data for a trusted contact' })
  @ApiResponse({ status: 200, description: 'Incident data' })
  @ApiResponse({ status: 401, description: 'Invalid or expired token' })
  @ApiResponse({ status: 404, description: 'Incident not found' })
  async getIncident(
    @Headers('authorization') authHeader: string,
  ) {
    const tokenData = await this.extractAndValidateToken(authHeader);

    // Fetch incident
    const incident = await this.incidentRepo.findOne({
      where: { id: tokenData.incidentId },
    });

    if (!incident) {
      throw new NotFoundException('Incident not found');
    }

    // Fetch user (person who triggered the alert)
    const user = await this.userRepo.findOne({
      where: { id: incident.userId },
    });

    // Fetch contact info
    const contact = await this.contactRepo.findOne({
      where: { id: tokenData.contactId },
    });

    // Fetch locations (trail)
    const locations = await this.locationRepo.find({
      where: { incidentId: incident.id },
      order: { timestamp: 'ASC' },
      take: 500,
    });

    // Fetch timeline events (non-internal only)
    const events = await this.eventRepo
      .createQueryBuilder('event')
      .where('event.incident_id = :incidentId', { incidentId: incident.id })
      .andWhere('event.is_internal = false')
      .orderBy('event.timestamp', 'ASC')
      .getMany();

    // Build the location trail
    const currentLocation = locations.length > 0
      ? locations[locations.length - 1]
      : null;

    const locationTrail = {
      current: currentLocation
        ? {
            lat: Number(currentLocation.latitude),
            lng: Number(currentLocation.longitude),
            timestamp: currentLocation.timestamp.toISOString(),
            accuracy: currentLocation.accuracy ?? undefined,
          }
        : { lat: 0, lng: 0, timestamp: new Date().toISOString() },
      trail: locations.map((loc) => ({
        lat: Number(loc.latitude),
        lng: Number(loc.longitude),
        timestamp: loc.timestamp.toISOString(),
        accuracy: loc.accuracy ?? undefined,
      })),
    };

    // Build timeline
    const timeline = events.map((evt) => ({
      id: evt.id,
      type: this.mapEventType(evt.type),
      message: this.buildEventMessage(evt),
      timestamp: evt.timestamp.toISOString(),
      metadata: evt.payload ?? {},
    }));

    // Build instructions based on incident status
    const instructions = this.buildInstructions(incident);

    return {
      id: incident.id,
      status: incident.status,
      personFirstName: user?.firstName ?? 'Someone',
      triggeredAt: incident.startedAt?.toISOString() ?? incident.createdAt?.toISOString(),
      resolvedAt: incident.resolvedAt?.toISOString() ?? undefined,
      location: locationTrail,
      timeline,
      audioClips: [], // Audio clips require separate S3 signed URLs — TODO
      transcriptSummary: undefined, // TODO: aggregate from transcripts
      instructions,
      contactId: tokenData.contactId,
      contactName: contact?.name ?? 'Contact',
    };
  }

  // ─── Contact response ─────────────────────────────────────────

  @Post('incident/:id/respond')
  @Public()
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Submit a contact response to an incident' })
  @ApiResponse({ status: 201, description: 'Response recorded' })
  @ApiResponse({ status: 401, description: 'Invalid or expired token' })
  async respondToIncident(
    @Headers('authorization') authHeader: string,
    @Param('id', ParseUUIDPipe) incidentId: string,
    @Body() dto: ContactRespondDto,
  ) {
    const tokenData = await this.extractAndValidateToken(authHeader);

    if (tokenData.incidentId !== incidentId) {
      throw new UnauthorizedException(
        'Access token is not valid for this incident',
      );
    }

    const response = await this.notificationsService.recordContactResponse(
      incidentId,
      tokenData.contactId,
      dto,
    );

    return {
      incidentId: response.incidentId,
      contactId: tokenData.contactId,
      responseType: response.responseType,
      timestamp: response.respondedAt?.toISOString(),
    };
  }

  // ─── Private helpers ──────────────────────────────────────────

  private async extractAndValidateToken(
    authHeader: string,
  ): Promise<ValidatedTokenData> {
    if (!authHeader) {
      throw new UnauthorizedException('Authorization header is required');
    }

    const token = authHeader.startsWith('Bearer ')
      ? authHeader.slice(7)
      : authHeader;

    if (!token) {
      throw new UnauthorizedException('Access token is required');
    }

    const tokenData = await this.contactAccessService.validateToken(token);

    if (!tokenData) {
      throw new UnauthorizedException('Invalid or expired access token');
    }

    return tokenData;
  }

  private mapEventType(type: string): string {
    const map: Record<string, string> = {
      trigger_activated: 'trigger',
      countdown_started: 'system',
      countdown_cancelled: 'status_change',
      incident_activated: 'status_change',
      incident_resolved: 'status_change',
      risk_score_changed: 'system',
      escalation_wave: 'system',
      alert_dispatched: 'system',
      alert_failed: 'system',
      contact_responded: 'contact_response',
      location_updated: 'location_update',
      audio_uploaded: 'audio_clip',
    };
    return map[type] ?? 'system';
  }

  private buildEventMessage(event: IncidentEvent): string {
    const messages: Record<string, string> = {
      trigger_activated: 'Emergency alert triggered',
      countdown_started: 'Countdown started',
      countdown_cancelled: 'Alert cancelled',
      incident_activated: 'Alert activated — contacts being notified',
      incident_resolved: 'Situation resolved — person confirmed safe',
      escalation_wave: `Escalation wave ${event.payload?.wave ?? ''} dispatched`,
      alert_dispatched: `Alert sent to ${event.payload?.contactName ?? 'contact'}`,
      contact_responded: `Contact responded: ${event.payload?.responseType ?? ''}`,
      risk_score_changed: `Risk level updated to ${event.payload?.newLevel ?? 'unknown'}`,
    };
    return messages[event.type] ?? event.type.replace(/_/g, ' ');
  }

  private buildInstructions(incident: Incident): string[] {
    const instructions: string[] = [];

    if (incident.status === 'active' || incident.status === 'escalated') {
      instructions.push(
        'Try to contact this person immediately by phone.',
        'If you cannot reach them, consider going to their last known location.',
        'If you believe they are in immediate danger, call emergency services (112/911).',
        'Use the response buttons below to let others know what action you are taking.',
      );
    } else if (incident.status === 'resolved' || incident.status === 'false_alarm') {
      instructions.push(
        'This situation has been resolved. The person has confirmed they are safe.',
      );
    }

    return instructions;
  }
}
