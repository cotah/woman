import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { NotFoundException } from '@nestjs/common';
import { TimelineService } from '../../src/modules/timeline/timeline.service';
import { Incident, RiskLevel } from '../../src/modules/incidents/entities/incident.entity';
import { IncidentEvent, IncidentEventType } from '../../src/modules/incidents/entities/incident-event.entity';
import { IncidentLocation } from '../../src/modules/incidents/entities/incident-location.entity';
import { RiskAssessment } from '../../src/modules/incidents/entities/risk-assessment.entity';

describe('Timeline Generation (Integration)', () => {
  let module: TestingModule;
  let timelineService: TimelineService;
  let mockIncidentRepo: any;
  let mockEventRepo: any;
  let mockLocationRepo: any;
  let mockRiskAssessmentRepo: any;

  const baseTime = new Date('2026-04-06T10:00:00Z');
  const timeOffset = (seconds: number) => new Date(baseTime.getTime() + seconds * 1000);

  const mockIncident = {
    id: 'inc-1',
    userId: 'user-1',
    status: 'active',
  };

  const mockEvents: Partial<IncidentEvent>[] = [
    {
      id: 'evt-1',
      incidentId: 'inc-1',
      type: IncidentEventType.TRIGGER_ACTIVATED,
      timestamp: timeOffset(0),
      payload: { triggerType: 'manual_button' },
      source: 'system',
      isInternal: false,
    },
    {
      id: 'evt-2',
      incidentId: 'inc-1',
      type: IncidentEventType.COUNTDOWN_STARTED,
      timestamp: timeOffset(1),
      payload: { countdownSeconds: 5 },
      source: 'system',
      isInternal: false,
    },
    {
      id: 'evt-3',
      incidentId: 'inc-1',
      type: IncidentEventType.INCIDENT_ACTIVATED,
      timestamp: timeOffset(6),
      payload: {},
      source: 'system',
      isInternal: false,
    },
    {
      id: 'evt-4',
      incidentId: 'inc-1',
      type: IncidentEventType.COERCION_DETECTED,
      timestamp: timeOffset(2),
      payload: { note: 'Internal coercion event' },
      source: 'system',
      isInternal: true,
    },
    {
      id: 'evt-5',
      incidentId: 'inc-1',
      type: IncidentEventType.SECRET_CANCEL,
      timestamp: timeOffset(3),
      payload: { note: 'Secret cancel' },
      source: 'system',
      isInternal: true,
    },
  ];

  const mockLocations: Partial<IncidentLocation>[] = [
    {
      id: 'loc-1',
      incidentId: 'inc-1',
      latitude: 48.8566,
      longitude: 2.3522,
      accuracy: 10,
      speed: null,
      heading: null,
      altitude: null,
      provider: 'gps',
      timestamp: timeOffset(0),
    },
    {
      id: 'loc-2',
      incidentId: 'inc-1',
      latitude: 48.8570,
      longitude: 2.3525,
      accuracy: 8,
      speed: 1.5,
      heading: null,
      altitude: null,
      provider: 'gps',
      timestamp: timeOffset(10),
    },
  ];

  const mockRiskAssessments: Partial<RiskAssessment>[] = [
    {
      id: 'ra-1',
      incidentId: 'inc-1',
      previousScore: 0,
      newScore: 70,
      previousLevel: RiskLevel.NONE,
      newLevel: RiskLevel.ALERT,
      ruleId: 'manual_panic_trigger',
      ruleName: 'Manual Panic Trigger',
      reason: 'User manually triggered a panic alert',
      signalType: 'manual_panic_trigger',
      timestamp: timeOffset(0),
    },
    {
      id: 'ra-2',
      incidentId: 'inc-1',
      previousScore: 70,
      newScore: 90,
      previousLevel: RiskLevel.ALERT,
      newLevel: RiskLevel.CRITICAL,
      ruleId: 'countdown_not_cancelled',
      ruleName: 'Countdown Not Cancelled',
      reason: 'Countdown expired without cancellation',
      signalType: 'countdown_not_cancelled',
      timestamp: timeOffset(6),
    },
  ];

  beforeEach(async () => {
    // Create mock QueryBuilder for events
    const mockEventQb = {
      where: jest.fn().mockReturnThis(),
      andWhere: jest.fn().mockReturnThis(),
      orderBy: jest.fn().mockReturnThis(),
      getMany: jest.fn(),
    };

    mockIncidentRepo = {
      findOne: jest.fn().mockResolvedValue(mockIncident),
    };

    mockEventRepo = {
      createQueryBuilder: jest.fn(() => {
        const qb = { ...mockEventQb };
        // Default: return all events (including internal)
        qb.getMany = jest.fn().mockResolvedValue([...mockEvents]);
        // Track if andWhere was called to filter internal events
        let filterInternal = false;
        qb.andWhere = jest.fn((condition: string) => {
          if (condition.includes('is_internal')) {
            filterInternal = true;
          }
          // If filtering internal, return only non-internal events
          qb.getMany = jest.fn().mockResolvedValue(
            filterInternal
              ? mockEvents.filter((e) => !e.isInternal)
              : [...mockEvents],
          );
          return qb;
        });
        return qb;
      }),
    };

    mockLocationRepo = {
      find: jest.fn().mockResolvedValue([...mockLocations]),
    };

    mockRiskAssessmentRepo = {
      find: jest.fn().mockResolvedValue([...mockRiskAssessments]),
    };

    module = await Test.createTestingModule({
      providers: [
        TimelineService,
        { provide: getRepositoryToken(Incident), useValue: mockIncidentRepo },
        { provide: getRepositoryToken(IncidentEvent), useValue: mockEventRepo },
        { provide: getRepositoryToken(IncidentLocation), useValue: mockLocationRepo },
        { provide: getRepositoryToken(RiskAssessment), useValue: mockRiskAssessmentRepo },
      ],
    }).compile();

    timelineService = module.get(TimelineService);
  });

  afterEach(async () => {
    await module.close();
  });

  describe('chronological ordering', () => {
    it('should return timeline entries in chronological order', async () => {
      const timeline = await timelineService.getTimeline('inc-1', 'user-1', true);

      for (let i = 1; i < timeline.length; i++) {
        const prev = new Date(timeline[i - 1].timestamp).getTime();
        const curr = new Date(timeline[i].timestamp).getTime();
        expect(curr).toBeGreaterThanOrEqual(prev);
      }
    });

    it('should include entries from all data sources', async () => {
      const timeline = await timelineService.getTimeline('inc-1', 'user-1', true);

      const categories = timeline.map((e) => e.category);
      expect(categories).toContain('event');
      expect(categories).toContain('location');
      expect(categories).toContain('risk_change');
    });
  });

  describe('all event types represented', () => {
    it('should include event entries with correct category', async () => {
      const timeline = await timelineService.getTimeline('inc-1', 'user-1', true);

      const eventEntries = timeline.filter((e) => e.category === 'event');
      expect(eventEntries.length).toBe(mockEvents.length);
    });

    it('should include location entries with lat/lng in summary', async () => {
      const timeline = await timelineService.getTimeline('inc-1', 'user-1', true);

      const locationEntries = timeline.filter((e) => e.category === 'location');
      expect(locationEntries.length).toBe(mockLocations.length);
      expect(locationEntries[0].summary).toContain('Location update');
      expect(locationEntries[0].data.latitude).toBe(48.8566);
    });

    it('should include risk_change entries with score transition', async () => {
      const timeline = await timelineService.getTimeline('inc-1', 'user-1', true);

      const riskEntries = timeline.filter((e) => e.category === 'risk_change');
      expect(riskEntries.length).toBe(mockRiskAssessments.length);
      expect(riskEntries[0].summary).toContain('0');
      expect(riskEntries[0].summary).toContain('70');
      expect(riskEntries[0].data.ruleId).toBe('manual_panic_trigger');
    });

    it('should format event type names as human-readable summaries', async () => {
      const timeline = await timelineService.getTimeline('inc-1', 'user-1', true);

      const triggerEvent = timeline.find(
        (e) => e.category === 'event' && e.data.type === IncidentEventType.TRIGGER_ACTIVATED,
      );
      expect(triggerEvent).toBeDefined();
      // "trigger_activated" -> "Trigger Activated"
      expect(triggerEvent!.summary).toBe('Trigger Activated');
    });
  });

  describe('internal events hidden from non-admin views', () => {
    it('should include internal events when includeInternal=true', async () => {
      const timeline = await timelineService.getTimeline('inc-1', 'user-1', true);

      const internalEntries = timeline.filter((e) => e.isInternal);
      expect(internalEntries.length).toBeGreaterThan(0);
    });

    it('should hide internal events when includeInternal=false', async () => {
      const timeline = await timelineService.getTimeline('inc-1', 'user-1', false);

      const internalEntries = timeline.filter((e) => e.isInternal);
      expect(internalEntries.length).toBe(0);
    });

    it('should not include COERCION_DETECTED or SECRET_CANCEL in non-admin view', async () => {
      const timeline = await timelineService.getTimeline('inc-1', 'user-1', false);

      const coercionEvents = timeline.filter(
        (e) =>
          e.category === 'event' &&
          (e.data.type === IncidentEventType.COERCION_DETECTED ||
            e.data.type === IncidentEventType.SECRET_CANCEL),
      );
      expect(coercionEvents.length).toBe(0);
    });
  });

  describe('ownership verification', () => {
    it('should throw NotFoundException for non-existent incident', async () => {
      mockIncidentRepo.findOne.mockResolvedValue(null);

      await expect(
        timelineService.getTimeline('nonexistent', 'user-1'),
      ).rejects.toThrow(NotFoundException);
    });

    // B2: unified ownership errors to 404 across the codebase
    // to prevent UUID enumeration attacks. A wrong-user request
    // is now indistinguishable from a non-existent incident.
    it('should not leak incident existence to wrong user', async () => {
      mockIncidentRepo.findOne.mockResolvedValue({
        ...mockIncident,
        userId: 'other-user',
      });

      await expect(
        timelineService.getTimeline('inc-1', 'user-1'),
      ).rejects.toThrow(NotFoundException);
    });
  });
});
