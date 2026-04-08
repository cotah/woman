import { RiskEngineService } from '../../src/modules/risk-engine/risk-engine.service';
import {
  IncidentRiskState,
  RiskSignal,
} from '../../src/modules/risk-engine/interfaces/risk-scoring-strategy';
import {
  IncidentStatus,
  RiskLevel,
  TriggerType,
} from '../../src/modules/incidents/entities/incident.entity';
import { IncidentEventType } from '../../src/modules/incidents/entities/incident-event.entity';
import { IncidentsService } from '../../src/modules/incidents/incidents.service';

describe('Coercion Logic', () => {
  // ─── Risk Engine: coercion scoring ────────────────────────────
  describe('RiskEngineService - coercion scoring', () => {
    let riskEngine: RiskEngineService;
    let mockRiskAssessmentRepo: any;

    beforeEach(() => {
      mockRiskAssessmentRepo = {
        find: jest.fn().mockResolvedValue([]),
        create: jest.fn((data) => data),
        save: jest.fn((data) => Promise.resolve({ id: 'ra-1', ...data })),
      };
      riskEngine = new RiskEngineService(mockRiskAssessmentRepo);
    });

    it('should jump score to critical (95) on coercion_pin signal', async () => {
      const signal: RiskSignal = { type: 'coercion_pin', payload: {} };
      const state: IncidentRiskState = {
        incidentId: 'inc-1',
        currentScore: 0,
        currentLevel: RiskLevel.NONE,
        isCoercion: true,
        isTestMode: false,
        triggerType: 'coercion_pin',
        eventCount: 0,
      };

      const result = await riskEngine.evaluate(signal, state);

      expect(result.newScore).toBe(95);
      expect(result.newLevel).toBe(RiskLevel.CRITICAL);
    });

    it('should clamp coercion score to 100 when previous score is non-zero', async () => {
      const signal: RiskSignal = { type: 'coercion_pin', payload: {} };
      const state: IncidentRiskState = {
        incidentId: 'inc-1',
        currentScore: 20,
        currentLevel: RiskLevel.MONITORING,
        isCoercion: true,
        isTestMode: false,
        triggerType: 'coercion_pin',
        eventCount: 0,
      };

      const result = await riskEngine.evaluate(signal, state);

      expect(result.newScore).toBe(100); // 20 + 95 clamped
      expect(result.newLevel).toBe(RiskLevel.CRITICAL);
    });
  });

  // ─── IncidentsService: coercion behavior ──────────────────────
  describe('IncidentsService - coercion behavior', () => {
    let incidentsService: IncidentsService;
    let mockIncidentRepo: any;
    let mockEventRepo: any;
    let mockLocationRepo: any;
    let mockRiskEngine: any;

    const createMockIncident = (overrides = {}) => ({
      id: 'inc-1',
      userId: 'user-1',
      status: IncidentStatus.COUNTDOWN,
      triggerType: TriggerType.MANUAL_BUTTON,
      isCoercion: false,
      isTestMode: false,
      currentRiskScore: 0,
      currentRiskLevel: RiskLevel.NONE,
      escalationWave: 0,
      startedAt: new Date(),
      countdownEndsAt: new Date(),
      activatedAt: null,
      resolvedAt: null,
      resolutionReason: null,
      lastLocationAt: null,
      lastLatitude: null,
      lastLongitude: null,
      createdAt: new Date(),
      updatedAt: new Date(),
      ...overrides,
    });

    beforeEach(() => {
      mockIncidentRepo = {
        findOne: jest.fn(),
        find: jest.fn(),
        create: jest.fn((data) => ({ id: 'inc-new', ...data })),
        save: jest.fn((data) => Promise.resolve(data)),
        createQueryBuilder: jest.fn(),
      };

      mockEventRepo = {
        create: jest.fn((data) => ({ id: 'evt-1', ...data })),
        save: jest.fn((data) => Promise.resolve(data)),
        createQueryBuilder: jest.fn(),
      };

      mockLocationRepo = {
        create: jest.fn((data) => data),
        save: jest.fn((data) => Promise.resolve(data)),
      };

      mockRiskEngine = {
        evaluate: jest.fn(),
        evaluateAndPersist: jest.fn().mockResolvedValue({
          result: {
            previousScore: 0,
            newScore: 95,
            previousLevel: RiskLevel.NONE,
            newLevel: RiskLevel.CRITICAL,
            scoreDelta: 95,
            ruleResults: [
              {
                ruleId: 'coercion_pin',
                ruleName: 'Coercion PIN Entered',
                scoreDelta: 95,
                reason: 'Coercion PIN was used',
                matched: true,
              },
            ],
            reasons: ['Coercion PIN was used'],
          },
          records: [],
        }),
      };

      incidentsService = new IncidentsService(
        mockIncidentRepo,
        mockEventRepo,
        mockLocationRepo,
        mockRiskEngine,
        { dispatchAlertWaves: jest.fn().mockResolvedValue(undefined), cancelPendingWaves: jest.fn().mockResolvedValue(undefined) } as any,
        { findAllByUser: jest.fn().mockResolvedValue([]) } as any,
        { generateToken: jest.fn().mockResolvedValue({ rawToken: 'test', accessUrl: 'http://test' }) } as any,
        { findById: jest.fn().mockResolvedValue({ id: 'user-1', firstName: 'Test', lastName: 'User', email: 'test@test.com' }) } as any,
      );
    });

    describe('secret cancel (coercion scenario)', () => {
      it('should return a response that looks cancelled to the caller', async () => {
        const incident = createMockIncident({
          status: IncidentStatus.COUNTDOWN,
        });
        mockIncidentRepo.findOne.mockResolvedValue(incident);
        mockIncidentRepo.save.mockImplementation((data: any) => Promise.resolve(data));

        const result = await incidentsService.cancel('inc-1', 'user-1', {
          isSecretCancel: true,
        });

        // The returned object should appear cancelled to the client
        expect(result.status).toBe(IncidentStatus.CANCELLED);
        expect(result.currentRiskScore).toBe(0);
        expect(result.currentRiskLevel).toBe(RiskLevel.NONE);
      });

      it('should internally set the incident to ESCALATED status', async () => {
        const incident = createMockIncident({
          status: IncidentStatus.COUNTDOWN,
        });
        mockIncidentRepo.findOne.mockResolvedValue(incident);

        let savedIncident: any;
        mockIncidentRepo.save.mockImplementation((data: any) => {
          savedIncident = { ...data };
          return Promise.resolve(data);
        });

        await incidentsService.cancel('inc-1', 'user-1', {
          isSecretCancel: true,
        });

        // The actual saved incident should be ESCALATED with critical risk
        expect(savedIncident.status).toBe(IncidentStatus.ESCALATED);
        expect(savedIncident.isCoercion).toBe(true);
        expect(savedIncident.currentRiskScore).toBeGreaterThanOrEqual(95);
        expect(savedIncident.currentRiskLevel).toBe(RiskLevel.CRITICAL);
      });

      it('should emit internal-only SECRET_CANCEL and COERCION_DETECTED events', async () => {
        const incident = createMockIncident({
          status: IncidentStatus.ACTIVE,
        });
        mockIncidentRepo.findOne.mockResolvedValue(incident);
        mockIncidentRepo.save.mockImplementation((data: any) => Promise.resolve(data));

        await incidentsService.cancel('inc-1', 'user-1', {
          isSecretCancel: true,
        });

        // Check events were created as internal
        const eventCalls = mockEventRepo.create.mock.calls;
        const secretCancelEvent = eventCalls.find(
          (call: any) => call[0].type === IncidentEventType.SECRET_CANCEL,
        );
        const coercionEvent = eventCalls.find(
          (call: any) => call[0].type === IncidentEventType.COERCION_DETECTED,
        );

        expect(secretCancelEvent).toBeDefined();
        expect(secretCancelEvent[0].isInternal).toBe(true);
        expect(coercionEvent).toBeDefined();
        expect(coercionEvent[0].isInternal).toBe(true);
      });

      it('should run coercion_pin risk signal through the risk engine', async () => {
        const incident = createMockIncident({
          status: IncidentStatus.COUNTDOWN,
        });
        mockIncidentRepo.findOne.mockResolvedValue(incident);
        mockIncidentRepo.save.mockImplementation((data: any) => Promise.resolve(data));

        await incidentsService.cancel('inc-1', 'user-1', {
          isSecretCancel: true,
        });

        expect(mockRiskEngine.evaluateAndPersist).toHaveBeenCalledWith(
          expect.objectContaining({ type: 'coercion_pin' }),
          expect.any(Object),
        );
      });
    });

    describe('create incident with coercion PIN', () => {
      it('should mark incident as coercion when triggerType is COERCION_PIN', async () => {
        mockIncidentRepo.findOne.mockResolvedValue(null); // no active incident

        await incidentsService.create('user-1', {
          triggerType: TriggerType.COERCION_PIN,
        });

        const createCall = mockIncidentRepo.create.mock.calls[0][0];
        expect(createCall.isCoercion).toBe(true);
      });

      it('should mark incident as coercion when isCoercion flag is true', async () => {
        mockIncidentRepo.findOne.mockResolvedValue(null);

        await incidentsService.create('user-1', {
          triggerType: TriggerType.MANUAL_BUTTON,
          isCoercion: true,
        });

        const createCall = mockIncidentRepo.create.mock.calls[0][0];
        expect(createCall.isCoercion).toBe(true);
      });

      it('should emit COERCION_DETECTED event when creating coercion incident', async () => {
        mockIncidentRepo.findOne.mockResolvedValue(null);

        await incidentsService.create('user-1', {
          triggerType: TriggerType.COERCION_PIN,
        });

        const eventTypes = mockEventRepo.create.mock.calls.map((c: any) => c[0].type);
        expect(eventTypes).toContain(IncidentEventType.COERCION_DETECTED);

        const coercionEvent = mockEventRepo.create.mock.calls.find(
          (c: any) => c[0].type === IncidentEventType.COERCION_DETECTED,
        );
        expect(coercionEvent[0].isInternal).toBe(true);
      });
    });
  });
});
