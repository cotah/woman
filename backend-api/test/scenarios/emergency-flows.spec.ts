import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { getQueueToken } from '@nestjs/bullmq';
import { IncidentsService } from '../../src/modules/incidents/incidents.service';
import { RiskEngineService } from '../../src/modules/risk-engine/risk-engine.service';
import { NotificationsService, TrustedContactInfo } from '../../src/modules/notifications/notifications.service';
import {
  Incident,
  IncidentStatus,
  TriggerType,
  RiskLevel,
} from '../../src/modules/incidents/entities/incident.entity';
import { IncidentEvent, IncidentEventType } from '../../src/modules/incidents/entities/incident-event.entity';
import { IncidentLocation } from '../../src/modules/incidents/entities/incident-location.entity';
import { RiskAssessment } from '../../src/modules/incidents/entities/risk-assessment.entity';
import { AlertDelivery } from '../../src/modules/notifications/entities/alert-delivery.entity';
import { ContactResponse } from '../../src/modules/notifications/entities/contact-response.entity';
import { SmsProvider } from '../../src/modules/notifications/providers/sms.provider';
import { PushProvider } from '../../src/modules/notifications/providers/push.provider';
import { VoiceProvider } from '../../src/modules/notifications/providers/voice.provider';
import { ContactsService } from '../../src/modules/contacts/contacts.service';
import { ContactAccessService } from '../../src/modules/contacts/contact-access.service';
import { UsersService } from '../../src/modules/users/users.service';

/**
 * End-to-end scenario tests that exercise full flows through the
 * incidents + risk-engine + notifications services together.
 */
describe('Emergency Flows (Scenarios)', () => {
  let module: TestingModule;
  let incidentsService: IncidentsService;
  let notificationsService: NotificationsService;
  let riskEngineService: RiskEngineService;

  // Track created artifacts
  let createdEvents: any[];
  let createdDeliveries: any[];
  let savedIncidents: any[];

  // Mock repos
  let mockIncidentRepo: any;
  let mockEventRepo: any;
  let mockLocationRepo: any;
  let mockRiskAssessmentRepo: any;
  let mockDeliveryRepo: any;
  let mockResponseRepo: any;
  let mockAlertQueue: any;
  let mockSmsProvider: any;
  let mockPushProvider: any;
  let mockVoiceProvider: any;

  const contacts: TrustedContactInfo[] = [
    {
      id: 'c1', name: 'Alice', phone: '+1111', pushToken: 'pt1',
      priority: 1, locale: 'en', canReceiveSms: true, canReceivePush: true, canReceiveVoiceCall: true,
    },
    {
      id: 'c2', name: 'Bob', phone: '+2222', pushToken: 'pt2',
      priority: 2, locale: 'en', canReceiveSms: true, canReceivePush: true, canReceiveVoiceCall: true,
    },
    {
      id: 'c3', name: 'Charlie', phone: '+3333', pushToken: 'pt3',
      priority: 3, locale: 'en', canReceiveSms: true, canReceivePush: true, canReceiveVoiceCall: true,
    },
  ];

  beforeEach(async () => {
    createdEvents = [];
    createdDeliveries = [];
    savedIncidents = [];

    mockIncidentRepo = {
      findOne: jest.fn().mockResolvedValue(null),
      create: jest.fn((data) => ({
        id: 'inc-scenario',
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
      create: jest.fn((data) => ({ id: `ra-${Math.random()}`, timestamp: new Date(), ...data })),
      save: jest.fn((data) => Promise.resolve(data)),
    };

    mockDeliveryRepo = {
      create: jest.fn((data) => {
        const delivery = { id: `del-${createdDeliveries.length + 1}`, ...data };
        createdDeliveries.push(delivery);
        return delivery;
      }),
      save: jest.fn((data) => Promise.resolve(data)),
      find: jest.fn().mockResolvedValue([]),
      findOne: jest.fn().mockResolvedValue(null),
      findOneOrFail: jest.fn(),
      update: jest.fn().mockResolvedValue({}),
      manager: {
        query: jest.fn().mockResolvedValue(undefined),
      },
    };

    mockResponseRepo = {
      create: jest.fn((data) => ({ id: 'resp-1', ...data })),
      save: jest.fn((data) => Promise.resolve(data)),
      find: jest.fn().mockResolvedValue([]),
    };

    mockAlertQueue = {
      add: jest.fn().mockResolvedValue({}),
      getJob: jest.fn().mockResolvedValue(null),
    };

    mockSmsProvider = {
      channel: 'sms',
      send: jest.fn().mockResolvedValue({ success: true, externalId: 'sms-1' }),
      getStatus: jest.fn(),
    };

    mockPushProvider = {
      channel: 'push',
      send: jest.fn().mockResolvedValue({ success: true, externalId: 'push-1' }),
      getStatus: jest.fn(),
    };

    mockVoiceProvider = {
      channel: 'voice_call',
      send: jest.fn().mockResolvedValue({ success: true, externalId: 'voice-1' }),
      getStatus: jest.fn(),
    };

    module = await Test.createTestingModule({
      providers: [
        IncidentsService,
        RiskEngineService,
        NotificationsService,
        { provide: getRepositoryToken(Incident), useValue: mockIncidentRepo },
        { provide: getRepositoryToken(IncidentEvent), useValue: mockEventRepo },
        { provide: getRepositoryToken(IncidentLocation), useValue: mockLocationRepo },
        { provide: getRepositoryToken(RiskAssessment), useValue: mockRiskAssessmentRepo },
        { provide: getRepositoryToken(AlertDelivery), useValue: mockDeliveryRepo },
        { provide: getRepositoryToken(ContactResponse), useValue: mockResponseRepo },
        { provide: getQueueToken('alert-dispatch'), useValue: mockAlertQueue },
        { provide: SmsProvider, useValue: mockSmsProvider },
        { provide: PushProvider, useValue: mockPushProvider },
        { provide: VoiceProvider, useValue: mockVoiceProvider },
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
    notificationsService = module.get(NotificationsService);
  });

  afterEach(async () => {
    await module.close();
  });

  // ─── Scenario 1: Manual trigger -> countdown -> not cancelled -> alerts -> contact responds -> resolved ──
  describe('Scenario: Manual trigger full flow to resolution', () => {
    it('should complete the full manual trigger flow', async () => {
      // Step 1: Create incident with manual trigger
      const incident = await incidentsService.create('user-1', {
        triggerType: TriggerType.MANUAL_BUTTON,
        location: { latitude: 48.8566, longitude: 2.3522 },
      });

      expect(incident.status).toBe(IncidentStatus.COUNTDOWN);
      expect(incident.currentRiskScore).toBe(70);
      expect(incident.currentRiskLevel).toBe(RiskLevel.ALERT);

      // Step 2: Countdown expires -> activate
      mockIncidentRepo.findOne.mockResolvedValue(incident);
      const activated = await incidentsService.activate('inc-scenario', 'user-1');

      expect(activated.status).toBe(IncidentStatus.ACTIVE);
      expect(activated.currentRiskScore).toBe(90); // 70 + 20 (countdown_not_cancelled)
      expect(activated.currentRiskLevel).toBe(RiskLevel.CRITICAL);

      // Step 3: Dispatch alerts to contacts
      await notificationsService.dispatchAlertWaves(
        'inc-scenario', 'user-1', 'Jane Doe', contacts,
      );

      expect(mockAlertQueue.add).toHaveBeenCalledTimes(3); // 3 waves

      // Step 4: Contact responds
      await notificationsService.recordContactResponse('inc-scenario', 'c1', {
        responseType: 'trying_to_reach',
        note: 'On my way',
      });

      expect(mockResponseRepo.save).toHaveBeenCalled();

      // Step 5: Resolve incident
      const resolved = await incidentsService.resolve('inc-scenario', 'user-1', {
        reason: 'User confirmed safe by Alice',
      });

      expect(resolved.status).toBe(IncidentStatus.RESOLVED);
      expect(resolved.resolutionReason).toBe('User confirmed safe by Alice');

      // Verify the full event trail
      const eventTypes = createdEvents.map((e) => e.type);
      expect(eventTypes).toContain(IncidentEventType.TRIGGER_ACTIVATED);
      expect(eventTypes).toContain(IncidentEventType.COUNTDOWN_STARTED);
      expect(eventTypes).toContain(IncidentEventType.RISK_SCORE_CHANGED);
      expect(eventTypes).toContain(IncidentEventType.INCIDENT_ACTIVATED);
      expect(eventTypes).toContain(IncidentEventType.INCIDENT_RESOLVED);
    });
  });

  // ─── Scenario 2: Coercion PIN -> appears cancelled -> silently escalated -> contacts notified ──
  describe('Scenario: Coercion PIN incident with secret cancel', () => {
    it('should appear cancelled to the caller but be escalated internally', async () => {
      // Step 1: Create incident with coercion PIN
      const incident = await incidentsService.create('user-1', {
        triggerType: TriggerType.COERCION_PIN,
      });

      expect(incident.isCoercion).toBe(true);
      expect(incident.currentRiskScore).toBe(95);
      expect(incident.currentRiskLevel).toBe(RiskLevel.CRITICAL);

      // Step 2: Secret cancel (appears cancelled but is escalated)
      mockIncidentRepo.findOne.mockResolvedValue(incident);

      let internalSavedState: any;
      mockIncidentRepo.save.mockImplementation((data: any) => {
        internalSavedState = { ...data };
        return Promise.resolve(data);
      });

      const cancelResult = await incidentsService.cancel('inc-scenario', 'user-1', {
        isSecretCancel: true,
      });

      // Client sees cancelled
      expect(cancelResult.status).toBe(IncidentStatus.CANCELLED);
      expect(cancelResult.currentRiskScore).toBe(0);

      // Internal state is ESCALATED
      expect(internalSavedState.status).toBe(IncidentStatus.ESCALATED);
      expect(internalSavedState.isCoercion).toBe(true);
      expect(internalSavedState.currentRiskScore).toBeGreaterThanOrEqual(95);
      expect(internalSavedState.currentRiskLevel).toBe(RiskLevel.CRITICAL);

      // Step 3: Dispatch silent alerts
      await notificationsService.dispatchAlertWaves(
        'inc-scenario', 'user-1', 'Jane Doe', contacts,
      );

      expect(mockAlertQueue.add).toHaveBeenCalled();

      // Verify coercion events were created as internal
      const internalEvents = createdEvents.filter((e) => e.isInternal === true);
      expect(internalEvents.length).toBeGreaterThan(0);
      const coercionEventTypes = internalEvents.map((e) => e.type);
      expect(coercionEventTypes).toContain(IncidentEventType.COERCION_DETECTED);
    });
  });

  // ─── Scenario 3: Manual trigger -> cancelled during countdown -> no alerts ──
  describe('Scenario: Manual trigger cancelled during countdown', () => {
    it('should cancel cleanly with no alerts sent', async () => {
      // Step 1: Create incident
      const incident = await incidentsService.create('user-1', {
        triggerType: TriggerType.MANUAL_BUTTON,
      });

      expect(incident.status).toBe(IncidentStatus.COUNTDOWN);

      // Step 2: Cancel during countdown
      mockIncidentRepo.findOne.mockResolvedValue(incident);
      const cancelled = await incidentsService.cancel('inc-scenario', 'user-1', {
        reason: 'Accidental trigger',
      });

      expect(cancelled.status).toBe(IncidentStatus.CANCELLED);
      expect(cancelled.resolutionReason).toBe('Accidental trigger');

      // No alerts should have been dispatched
      expect(mockSmsProvider.send).not.toHaveBeenCalled();
      expect(mockPushProvider.send).not.toHaveBeenCalled();
      expect(mockVoiceProvider.send).not.toHaveBeenCalled();

      // Verify countdown_cancelled event was created
      const cancelEvent = createdEvents.find(
        (e) => e.type === IncidentEventType.COUNTDOWN_CANCELLED,
      );
      expect(cancelEvent).toBeDefined();
    });
  });

  // ─── Scenario 4: Audio enabled incident -> chunks uploaded -> transcription queued ──
  describe('Scenario: Audio enabled incident with event tracking', () => {
    it('should track audio chunk uploads and transcription events', async () => {
      // Step 1: Create incident
      const incident = await incidentsService.create('user-1', {
        triggerType: TriggerType.MANUAL_BUTTON,
      });

      // Step 2: Activate
      mockIncidentRepo.findOne.mockResolvedValue(incident);
      const activated = await incidentsService.activate('inc-scenario', 'user-1');

      // Step 3: Add audio chunk event
      mockIncidentRepo.findOne.mockResolvedValue(activated);
      const audioEvent = await incidentsService.addEvent('inc-scenario', 'user-1', {
        type: IncidentEventType.AUDIO_CHUNK_UPLOADED,
        payload: {
          chunkIndex: 0,
          durationMs: 5000,
          s3Key: 'audio/inc-scenario/chunk-0.webm',
        },
        source: 'client',
      });

      expect(audioEvent.type).toBe(IncidentEventType.AUDIO_CHUNK_UPLOADED);

      // Step 4: Add transcription completed event
      const transcriptionEvent = await incidentsService.addEvent('inc-scenario', 'user-1', {
        type: IncidentEventType.TRANSCRIPTION_COMPLETED,
        payload: {
          chunkIndex: 0,
          text: 'Help me please',
          confidence: 0.95,
        },
        source: 'system',
      });

      expect(transcriptionEvent.type).toBe(IncidentEventType.TRANSCRIPTION_COMPLETED);

      // Verify events were tracked
      const audioEvents = createdEvents.filter(
        (e) =>
          e.type === IncidentEventType.AUDIO_CHUNK_UPLOADED ||
          e.type === IncidentEventType.TRANSCRIPTION_COMPLETED,
      );
      expect(audioEvents.length).toBeGreaterThanOrEqual(2);
    });
  });

  // ─── Scenario 5: Test mode -> full flow -> no real alerts ──
  describe('Scenario: Test mode incident', () => {
    it('should run the full flow without liveOnly risk rules', async () => {
      // Step 1: Create test mode incident
      const incident = await incidentsService.create('user-1', {
        triggerType: TriggerType.MANUAL_BUTTON,
        isTestMode: true,
      });

      expect(incident.isTestMode).toBe(true);
      expect(incident.status).toBe(IncidentStatus.COUNTDOWN);
      // manual_panic_trigger is NOT liveOnly, so it still fires
      expect(incident.currentRiskScore).toBe(70);

      // Step 2: Activate
      mockIncidentRepo.findOne.mockResolvedValue(incident);
      const activated = await incidentsService.activate('inc-scenario', 'user-1');
      expect(activated.status).toBe(IncidentStatus.ACTIVE);

      // Step 3: Process a liveOnly signal (rapid_movement) - should be skipped
      const signal = { type: 'rapid_movement', payload: {} };
      const riskState = {
        incidentId: 'inc-scenario',
        currentScore: activated.currentRiskScore,
        currentLevel: activated.currentRiskLevel,
        isCoercion: false,
        isTestMode: true,
        triggerType: 'manual_button',
        eventCount: 0,
      };

      const riskResult = await riskEngineService.evaluate(signal, riskState);
      // rapid_movement is liveOnly, should be skipped in test mode
      expect(riskResult.scoreDelta).toBe(0);
      expect(riskResult.ruleResults[0].matched).toBe(false);

      // Step 4: Resolve
      const resolved = await incidentsService.resolve('inc-scenario', 'user-1', {
        reason: 'Test completed',
      });
      expect(resolved.status).toBe(IncidentStatus.RESOLVED);
    });
  });

  // ─── Scenario 6: No contact response -> escalation waves fire ──
  describe('Scenario: No contact response triggers escalation waves', () => {
    it('should schedule all escalation waves when incident is activated', async () => {
      // Step 1: Create and activate incident
      const incident = await incidentsService.create('user-1', {
        triggerType: TriggerType.MANUAL_BUTTON,
      });

      mockIncidentRepo.findOne.mockResolvedValue(incident);
      const activated = await incidentsService.activate('inc-scenario', 'user-1');

      // Step 2: Dispatch alert waves (simulating what happens after activation)
      await notificationsService.dispatchAlertWaves(
        'inc-scenario', 'user-1', 'Jane Doe', contacts,
      );

      // All 3 waves should be scheduled
      expect(mockAlertQueue.add).toHaveBeenCalledTimes(3);

      // Wave 1: immediate (delay=0), priority 1-2
      const wave1 = mockAlertQueue.add.mock.calls[0];
      expect(wave1[1].wave).toBe(1);
      expect(wave1[1].maxPriority).toBe(2);
      expect(wave1[2].delay).toBe(0);

      // Wave 2: after 60s, priority 1-4
      const wave2 = mockAlertQueue.add.mock.calls[1];
      expect(wave2[1].wave).toBe(2);
      expect(wave2[1].maxPriority).toBe(4);
      expect(wave2[2].delay).toBe(60_000);

      // Wave 3: after 120s, all contacts
      const wave3 = mockAlertQueue.add.mock.calls[2];
      expect(wave3[1].wave).toBe(3);
      expect(wave3[1].maxPriority).toBe(999);
      expect(wave3[2].delay).toBe(120_000);

      // Step 3: Execute wave 1 (no response from contacts)
      await notificationsService.executeWave({
        incidentId: 'inc-scenario',
        userId: 'user-1',
        userName: 'Jane Doe',
        wave: 1,
        maxPriority: 2,
        channels: ['push', 'sms'],
        contacts,
      });

      // Only priority 1-2 contacts should have deliveries
      const wave1ContactIds = [...new Set(createdDeliveries.map((d) => d.contactId))];
      expect(wave1ContactIds).toContain('c1');
      expect(wave1ContactIds).toContain('c2');
      expect(wave1ContactIds).not.toContain('c3');

      // Step 4: Execute wave 2 (still no response, escalate to more contacts + voice)
      await notificationsService.executeWave({
        incidentId: 'inc-scenario',
        userId: 'user-1',
        userName: 'Jane Doe',
        wave: 2,
        maxPriority: 4,
        channels: ['push', 'sms', 'voice_call'],
        contacts,
      });

      // Charlie (priority 3) should now have deliveries
      const allContactIds = [...new Set(createdDeliveries.map((d) => d.contactId))];
      expect(allContactIds).toContain('c3');

      // Voice calls should now be dispatched
      expect(mockVoiceProvider.send).toHaveBeenCalled();
    });
  });

  // ─── Scenario 7: Risk signal escalates active incident to critical ──
  describe('Scenario: Risk signal auto-escalates incident status', () => {
    it('should auto-escalate ACTIVE to ESCALATED when risk reaches critical', async () => {
      const activeIncident = {
        id: 'inc-scenario',
        userId: 'user-1',
        status: IncidentStatus.ACTIVE,
        triggerType: TriggerType.MANUAL_BUTTON,
        isCoercion: false,
        isTestMode: false,
        currentRiskScore: 60,
        currentRiskLevel: RiskLevel.SUSPICIOUS,
        escalationWave: 0,
        startedAt: new Date(),
        countdownEndsAt: new Date(),
        activatedAt: new Date(),
      };

      mockIncidentRepo.findOne.mockResolvedValue(activeIncident);

      const result = await incidentsService.processRiskSignal(
        'inc-scenario',
        'user-1',
        { type: 'help_phrase_detected', payload: { text: 'Help me' } },
      );

      // 60 + 35 = 95 -> CRITICAL
      expect(result.currentRiskScore).toBe(95);
      expect(result.currentRiskLevel).toBe(RiskLevel.CRITICAL);
      expect(result.status).toBe(IncidentStatus.ESCALATED);
      expect(result.escalationWave).toBe(1);

      // Verify escalation wave event was created
      const escalationEvent = createdEvents.find(
        (e) => e.type === IncidentEventType.ESCALATION_WAVE,
      );
      expect(escalationEvent).toBeDefined();
    });
  });
});
