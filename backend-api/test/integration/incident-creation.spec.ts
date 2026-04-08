import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { IncidentsService } from '../../src/modules/incidents/incidents.service';
import { RiskEngineService } from '../../src/modules/risk-engine/risk-engine.service';
import { NotificationsService } from '../../src/modules/notifications/notifications.service';
import { ContactsService } from '../../src/modules/contacts/contacts.service';
import { ContactAccessService } from '../../src/modules/contacts/contact-access.service';
import { UsersService } from '../../src/modules/users/users.service';
import {
  Incident,
  IncidentStatus,
  TriggerType,
  RiskLevel,
} from '../../src/modules/incidents/entities/incident.entity';
import { IncidentEvent, IncidentEventType } from '../../src/modules/incidents/entities/incident-event.entity';
import { IncidentLocation } from '../../src/modules/incidents/entities/incident-location.entity';
import { RiskAssessment } from '../../src/modules/incidents/entities/risk-assessment.entity';

describe('Incident Creation (Integration)', () => {
  let module: TestingModule;
  let incidentsService: IncidentsService;
  let riskEngineService: RiskEngineService;
  let mockIncidentRepo: any;
  let mockEventRepo: any;
  let mockLocationRepo: any;
  let mockRiskAssessmentRepo: any;

  // Track all events created
  let createdEvents: any[];
  let savedIncidents: any[];

  beforeEach(async () => {
    createdEvents = [];
    savedIncidents = [];

    mockIncidentRepo = {
      findOne: jest.fn().mockResolvedValue(null), // no existing active incident
      create: jest.fn((data) => ({
        id: 'inc-integration-1',
        createdAt: new Date(),
        updatedAt: new Date(),
        ...data,
      })),
      save: jest.fn((data) => {
        savedIncidents.push({ ...data });
        return Promise.resolve(data);
      }),
      createQueryBuilder: jest.fn(() => ({
        where: jest.fn().mockReturnThis(),
        andWhere: jest.fn().mockReturnThis(),
        orderBy: jest.fn().mockReturnThis(),
        skip: jest.fn().mockReturnThis(),
        take: jest.fn().mockReturnThis(),
        getManyAndCount: jest.fn().mockResolvedValue([[], 0]),
      })),
    };

    mockEventRepo = {
      create: jest.fn((data) => {
        const event = { id: `evt-${createdEvents.length + 1}`, createdAt: new Date(), ...data };
        createdEvents.push(event);
        return event;
      }),
      save: jest.fn((data) => Promise.resolve(data)),
      createQueryBuilder: jest.fn(() => ({
        where: jest.fn().mockReturnThis(),
        andWhere: jest.fn().mockReturnThis(),
        orderBy: jest.fn().mockReturnThis(),
        getMany: jest.fn().mockResolvedValue(createdEvents),
      })),
    };

    mockLocationRepo = {
      create: jest.fn((data) => ({ id: 'loc-1', ...data })),
      save: jest.fn((data) => Promise.resolve(data)),
    };

    mockRiskAssessmentRepo = {
      find: jest.fn().mockResolvedValue([]),
      create: jest.fn((data) => ({ id: 'ra-1', timestamp: new Date(), ...data })),
      save: jest.fn((data) => Promise.resolve(data)),
    };

    module = await Test.createTestingModule({
      providers: [
        IncidentsService,
        RiskEngineService,
        { provide: getRepositoryToken(Incident), useValue: mockIncidentRepo },
        { provide: getRepositoryToken(IncidentEvent), useValue: mockEventRepo },
        { provide: getRepositoryToken(IncidentLocation), useValue: mockLocationRepo },
        { provide: getRepositoryToken(RiskAssessment), useValue: mockRiskAssessmentRepo },
        {
          provide: NotificationsService,
          useValue: {
            dispatchAlertWaves: jest.fn().mockResolvedValue(undefined),
            cancelPendingWaves: jest.fn().mockResolvedValue(undefined),
          },
        },
        {
          provide: ContactsService,
          useValue: {
            findAllByUser: jest.fn().mockResolvedValue([]),
          },
        },
        {
          provide: ContactAccessService,
          useValue: {
            generateToken: jest.fn().mockResolvedValue({ rawToken: 'test', accessUrl: 'http://test' }),
          },
        },
        {
          provide: UsersService,
          useValue: {
            findById: jest.fn().mockResolvedValue({ id: 'user-1', firstName: 'Test', lastName: 'User', email: 'test@example.com' }),
          },
        },
      ],
    }).compile();

    incidentsService = module.get(IncidentsService);
    riskEngineService = module.get(RiskEngineService);
  });

  afterEach(async () => {
    await module.close();
  });

  describe('create incident with manual trigger', () => {
    it('should create an incident in COUNTDOWN status', async () => {
      const incident = await incidentsService.create('user-1', {
        triggerType: TriggerType.MANUAL_BUTTON,
      });

      expect(incident.status).toBe(IncidentStatus.COUNTDOWN);
      expect(incident.triggerType).toBe(TriggerType.MANUAL_BUTTON);
      expect(incident.isCoercion).toBe(false);
      expect(incident.isTestMode).toBe(false);
    });

    it('should set risk score from manual_panic_trigger rule (70 points)', async () => {
      const incident = await incidentsService.create('user-1', {
        triggerType: TriggerType.MANUAL_BUTTON,
      });

      expect(incident.currentRiskScore).toBe(70);
      expect(incident.currentRiskLevel).toBe(RiskLevel.ALERT);
    });

    it('should emit trigger_activated and countdown_started events', async () => {
      await incidentsService.create('user-1', {
        triggerType: TriggerType.MANUAL_BUTTON,
      });

      const eventTypes = createdEvents.map((e) => e.type);
      expect(eventTypes).toContain(IncidentEventType.TRIGGER_ACTIVATED);
      expect(eventTypes).toContain(IncidentEventType.COUNTDOWN_STARTED);
    });

    it('should emit risk_score_changed event when score changes', async () => {
      await incidentsService.create('user-1', {
        triggerType: TriggerType.MANUAL_BUTTON,
      });

      const riskEvent = createdEvents.find((e) => e.type === IncidentEventType.RISK_SCORE_CHANGED);
      expect(riskEvent).toBeDefined();
      expect(riskEvent.payload.newScore).toBe(70);
    });

    it('should save initial location when provided', async () => {
      await incidentsService.create('user-1', {
        triggerType: TriggerType.MANUAL_BUTTON,
        location: { latitude: 48.8566, longitude: 2.3522, accuracy: 10 },
      });

      expect(mockLocationRepo.create).toHaveBeenCalledWith(
        expect.objectContaining({
          latitude: 48.8566,
          longitude: 2.3522,
          accuracy: 10,
        }),
      );
      expect(mockLocationRepo.save).toHaveBeenCalled();
    });
  });

  describe('create incident with coercion flag', () => {
    it('should mark incident as coercion and run coercion_pin risk signal', async () => {
      const incident = await incidentsService.create('user-1', {
        triggerType: TriggerType.COERCION_PIN,
      });

      expect(incident.isCoercion).toBe(true);
      expect(incident.currentRiskScore).toBe(95);
      expect(incident.currentRiskLevel).toBe(RiskLevel.CRITICAL);
    });

    it('should emit COERCION_DETECTED event as internal', async () => {
      await incidentsService.create('user-1', {
        triggerType: TriggerType.COERCION_PIN,
      });

      const coercionEvent = createdEvents.find(
        (e) => e.type === IncidentEventType.COERCION_DETECTED,
      );
      expect(coercionEvent).toBeDefined();
      expect(coercionEvent.isInternal).toBe(true);
    });
  });

  describe('incident status transitions', () => {
    it('should transition from COUNTDOWN to ACTIVE on activate', async () => {
      const countdownIncident = {
        id: 'inc-1',
        userId: 'user-1',
        status: IncidentStatus.COUNTDOWN,
        triggerType: TriggerType.MANUAL_BUTTON,
        isCoercion: false,
        isTestMode: false,
        currentRiskScore: 70,
        currentRiskLevel: RiskLevel.ALERT,
        escalationWave: 0,
        startedAt: new Date(),
        countdownEndsAt: new Date(),
        activatedAt: null,
      };
      mockIncidentRepo.findOne.mockResolvedValue(countdownIncident);

      const activated = await incidentsService.activate('inc-1', 'user-1');

      expect(activated.status).toBe(IncidentStatus.ACTIVE);
      expect(activated.activatedAt).toBeDefined();
      // After countdown_not_cancelled (20 pts), score should be 90
      expect(activated.currentRiskScore).toBe(90);
      expect(activated.currentRiskLevel).toBe(RiskLevel.CRITICAL);
    });

    it('should transition from ACTIVE to RESOLVED on resolve', async () => {
      const activeIncident = {
        id: 'inc-1',
        userId: 'user-1',
        status: IncidentStatus.ACTIVE,
        triggerType: TriggerType.MANUAL_BUTTON,
        isCoercion: false,
        isTestMode: false,
        currentRiskScore: 90,
        currentRiskLevel: RiskLevel.CRITICAL,
        escalationWave: 0,
      };
      mockIncidentRepo.findOne.mockResolvedValue(activeIncident);

      const resolved = await incidentsService.resolve('inc-1', 'user-1', {
        reason: 'User is safe',
      });

      expect(resolved.status).toBe(IncidentStatus.RESOLVED);
      expect(resolved.resolvedAt).toBeDefined();
      expect(resolved.resolutionReason).toBe('User is safe');
    });

    it('should transition from COUNTDOWN to CANCELLED on normal cancel', async () => {
      const countdownIncident = {
        id: 'inc-1',
        userId: 'user-1',
        status: IncidentStatus.COUNTDOWN,
        triggerType: TriggerType.MANUAL_BUTTON,
        isCoercion: false,
        isTestMode: false,
        currentRiskScore: 70,
        currentRiskLevel: RiskLevel.ALERT,
        escalationWave: 0,
      };
      mockIncidentRepo.findOne.mockResolvedValue(countdownIncident);

      const cancelled = await incidentsService.cancel('inc-1', 'user-1', {
        reason: 'False alarm',
      });

      expect(cancelled.status).toBe(IncidentStatus.CANCELLED);
      expect(cancelled.resolutionReason).toBe('False alarm');
    });

    it('should mark as FALSE_ALARM when resolving with isFalseAlarm=true', async () => {
      const activeIncident = {
        id: 'inc-1',
        userId: 'user-1',
        status: IncidentStatus.ACTIVE,
        triggerType: TriggerType.MANUAL_BUTTON,
        isCoercion: false,
        isTestMode: false,
        currentRiskScore: 70,
        currentRiskLevel: RiskLevel.ALERT,
        escalationWave: 0,
      };
      mockIncidentRepo.findOne.mockResolvedValue(activeIncident);

      const resolved = await incidentsService.resolve('inc-1', 'user-1', {
        isFalseAlarm: true,
        reason: 'Accidental trigger',
      });

      expect(resolved.status).toBe(IncidentStatus.FALSE_ALARM);
    });
  });

  describe('test mode incidents', () => {
    it('should create incident with isTestMode=true', async () => {
      const incident = await incidentsService.create('user-1', {
        triggerType: TriggerType.MANUAL_BUTTON,
        isTestMode: true,
      });

      expect(incident.isTestMode).toBe(true);
    });

    it('should skip liveOnly risk rules in test mode', async () => {
      // The manual_panic_trigger rule is NOT liveOnly, so it still fires
      const incident = await incidentsService.create('user-1', {
        triggerType: TriggerType.MANUAL_BUTTON,
        isTestMode: true,
      });

      // Score should still be 70 because manual_panic_trigger is not liveOnly
      expect(incident.currentRiskScore).toBe(70);
    });

    it('should filter test mode incidents in findAll', async () => {
      const qb = {
        where: jest.fn().mockReturnThis(),
        andWhere: jest.fn().mockReturnThis(),
        orderBy: jest.fn().mockReturnThis(),
        skip: jest.fn().mockReturnThis(),
        take: jest.fn().mockReturnThis(),
        getManyAndCount: jest.fn().mockResolvedValue([[], 0]),
      };
      mockIncidentRepo.createQueryBuilder.mockReturnValue(qb);

      await incidentsService.findAll('user-1', { isTestMode: true });

      expect(qb.andWhere).toHaveBeenCalledWith(
        'incident.is_test_mode = :isTestMode',
        { isTestMode: true },
      );
    });
  });

  describe('error handling', () => {
    it('should reject creating a second incident when one is already active', async () => {
      mockIncidentRepo.findOne.mockResolvedValue({
        id: 'existing-inc',
        userId: 'user-1',
        status: IncidentStatus.ACTIVE,
      });

      await expect(
        incidentsService.create('user-1', {
          triggerType: TriggerType.MANUAL_BUTTON,
        }),
      ).rejects.toThrow('An active incident already exists');
    });
  });
});
