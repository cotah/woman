import { Injectable, Logger, NotFoundException, ForbiddenException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Incident } from '../incidents/entities/incident.entity';
import { IncidentEvent } from '../incidents/entities/incident-event.entity';
import { IncidentLocation } from '../incidents/entities/incident-location.entity';
import { RiskAssessment } from '../incidents/entities/risk-assessment.entity';

/**
 * A single entry in the unified timeline.
 */
export interface TimelineEntry {
  /** Unique ID of the source record */
  id: string;
  /** Category of this timeline entry */
  category: 'event' | 'location' | 'risk_change' | 'response';
  /** Timestamp for chronological sorting */
  timestamp: Date;
  /** Human-readable summary */
  summary: string;
  /** Full data payload */
  data: Record<string, any>;
  /** Whether this entry is internal (hidden from the client/contacts) */
  isInternal: boolean;
}

@Injectable()
export class TimelineService {
  private readonly logger = new Logger(TimelineService.name);

  constructor(
    @InjectRepository(Incident)
    private readonly incidentRepo: Repository<Incident>,
    @InjectRepository(IncidentEvent)
    private readonly eventRepo: Repository<IncidentEvent>,
    @InjectRepository(IncidentLocation)
    private readonly locationRepo: Repository<IncidentLocation>,
    @InjectRepository(RiskAssessment)
    private readonly riskAssessmentRepo: Repository<RiskAssessment>,
  ) {}

  /**
   * Build a unified, chronologically sorted timeline for an incident.
   *
   * Merges:
   * - Incident events (trigger, countdown, activation, resolution, etc.)
   * - Location updates
   * - Risk score changes
   *
   * @param incidentId - The incident to build the timeline for
   * @param userId - The requesting user (for ownership check)
   * @param includeInternal - Whether to include internal/system-only entries
   */
  async getTimeline(
    incidentId: string,
    userId: string,
    includeInternal = false,
  ): Promise<TimelineEntry[]> {
    // Verify ownership
    const incident = await this.incidentRepo.findOne({
      where: { id: incidentId },
    });

    if (!incident) {
      throw new NotFoundException(`Incident ${incidentId} not found`);
    }

    if (incident.userId !== userId) {
      throw new ForbiddenException('You do not have access to this incident');
    }

    // Fetch all data sources in parallel
    const [events, locations, riskAssessments] = await Promise.all([
      this.fetchEvents(incidentId, includeInternal),
      this.fetchLocations(incidentId),
      this.fetchRiskAssessments(incidentId),
    ]);

    // Convert each source into timeline entries
    const entries: TimelineEntry[] = [
      ...events.map((e) => this.eventToEntry(e)),
      ...locations.map((l) => this.locationToEntry(l)),
      ...riskAssessments.map((r) => this.riskAssessmentToEntry(r)),
    ];

    // Filter internal entries if not requested
    const filtered = includeInternal
      ? entries
      : entries.filter((e) => !e.isInternal);

    // Sort chronologically
    filtered.sort(
      (a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime(),
    );

    this.logger.debug(
      `Timeline for incident ${incidentId}: ${filtered.length} entries ` +
        `(${events.length} events, ${locations.length} locations, ${riskAssessments.length} risk changes)`,
    );

    return filtered;
  }

  // ─── Private helpers ──────────────────────────────────────────

  private async fetchEvents(
    incidentId: string,
    includeInternal: boolean,
  ): Promise<IncidentEvent[]> {
    const qb = this.eventRepo
      .createQueryBuilder('event')
      .where('event.incident_id = :incidentId', { incidentId })
      .orderBy('event.timestamp', 'ASC');

    if (!includeInternal) {
      qb.andWhere('event.is_internal = false');
    }

    return qb.getMany();
  }

  private async fetchLocations(incidentId: string): Promise<IncidentLocation[]> {
    return this.locationRepo.find({
      where: { incidentId },
      order: { timestamp: 'ASC' },
    });
  }

  private async fetchRiskAssessments(incidentId: string): Promise<RiskAssessment[]> {
    return this.riskAssessmentRepo.find({
      where: { incidentId },
      order: { timestamp: 'ASC' },
    });
  }

  private eventToEntry(event: IncidentEvent): TimelineEntry {
    const typeLabel = event.type
      .replace(/_/g, ' ')
      .replace(/\b\w/g, (c) => c.toUpperCase());

    return {
      id: event.id,
      category: 'event',
      timestamp: event.timestamp,
      summary: typeLabel,
      data: {
        type: event.type,
        payload: event.payload,
        source: event.source,
      },
      isInternal: event.isInternal,
    };
  }

  private locationToEntry(location: IncidentLocation): TimelineEntry {
    return {
      id: location.id,
      category: 'location',
      timestamp: location.timestamp,
      summary: `Location update (${location.latitude.toFixed(4)}, ${location.longitude.toFixed(4)})`,
      data: {
        latitude: location.latitude,
        longitude: location.longitude,
        accuracy: location.accuracy,
        speed: location.speed,
        heading: location.heading,
        altitude: location.altitude,
        provider: location.provider,
      },
      isInternal: false,
    };
  }

  private riskAssessmentToEntry(assessment: RiskAssessment): TimelineEntry {
    return {
      id: assessment.id,
      category: 'risk_change',
      timestamp: assessment.timestamp,
      summary: `Risk: ${assessment.previousScore} -> ${assessment.newScore} (${assessment.previousLevel} -> ${assessment.newLevel})`,
      data: {
        previousScore: assessment.previousScore,
        newScore: assessment.newScore,
        previousLevel: assessment.previousLevel,
        newLevel: assessment.newLevel,
        ruleId: assessment.ruleId,
        ruleName: assessment.ruleName,
        reason: assessment.reason,
        signalType: assessment.signalType,
      },
      isInternal: false,
    };
  }
}
