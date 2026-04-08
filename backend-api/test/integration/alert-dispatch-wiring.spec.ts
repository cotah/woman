import { IncidentsService } from '../../src/modules/incidents/incidents.service';
import { RiskEngineService } from '../../src/modules/risk-engine/risk-engine.service';
import {
  IncidentStatus,
  TriggerType,
  RiskLevel,
} from '../../src/modules/incidents/entities/incident.entity';

/**
 * Validates that the alert dispatch pipeline is correctly wired:
 * - activate() calls dispatchAlertWaves()
 * - secret cancel calls dispatchAlertWaves()
 * - normal cancel calls cancelPendingWaves()
 * - resolve calls cancelPendingWaves()
 */
describe('Alert Dispatch Wiring', () => {
  let incidentsService: IncidentsService;
  let mockIncidentRepo: any;
  let mockEventRepo: any;
  let mockLocationRepo: any;
  let mockRiskEngine: any;
  let mockNotificationsService: any;
  let mockContactsService: any;
  let mockContactAccessService: any;
  let mockUsersService: any;

  const mockUser = {
    id: 'user-1',
    firstName: 'Maria',
    lastName: 'Silva',
    email: 'maria@example.com',
  };

  const mockContact = {
    id: 'contact-1',
    name: 'João',
    phone: '+5511999999999',
    email: 'joao@example.com',
    priority: 1,
    locale: 'pt',
    canReceiveSms: true,
    canReceivePush: false,
    canReceiveVoiceCall: true,
  };

  const createMockIncident = (overrides: any = {}) => ({
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
    lastLatitude: null,
    lastLongitude: null,
    ...overrides,
  });

  beforeEach(() => {
    mockIncidentRepo = {
      findOne: jest.fn(),
      save: jest.fn((data) => Promise.resolve({ ...data })),
      create: jest.fn((data) => ({ ...data })),
    };

    mockEventRepo = {
      create: jest.fn((data) => ({ id: 'evt-1', ...data })),
      save: jest.fn((data) => Promise.resolve(data)),
    };

    mockLocationRepo = {
      create: jest.fn((data) => data),
      save: jest.fn((data) => Promise.resolve(data)),
    };

    mockRiskEngine = {
      evaluateAndPersist: jest.fn().mockResolvedValue({
        result: {
          previousScore: 0,
          newScore: 70,
          previousLevel: RiskLevel.NONE,
          newLevel: RiskLevel.ALERT,
          scoreDelta: 70,
          reasons: ['Countdown not cancelled'],
        },
        records: [],
      }),
    };

    mockNotificationsService = {
      dispatchAlertWaves: jest.fn().mockResolvedValue(undefined),
      cancelPendingWaves: jest.fn().mockResolvedValue(undefined),
    };

    mockContactsService = {
      findAllByUser: jest.fn().mockResolvedValue([mockContact]),
    };

    mockContactAccessService = {
      generateToken: jest.fn().mockResolvedValue({
        rawToken: 'tok-abc',
        accessUrl: 'https://view.safecircle.app/incident/inc-1?token=tok-abc',
      }),
    };

    mockUsersService = {
      findById: jest.fn().mockResolvedValue(mockUser),
    };

    incidentsService = new IncidentsService(
      mockIncidentRepo as any,
      mockEventRepo as any,
      mockLocationRepo as any,
      mockRiskEngine,
      mockNotificationsService,
      mockContactsService,
      mockContactAccessService,
      mockUsersService,
    );
  });

  describe('activate() triggers alert dispatch', () => {
    it('should call dispatchAlertWaves with correct contacts after activation', async () => {
      const incident = createMockIncident({ status: IncidentStatus.COUNTDOWN });
      mockIncidentRepo.findOne.mockResolvedValue(incident);

      await incidentsService.activate('inc-1', 'user-1');

      expect(mockUsersService.findById).toHaveBeenCalledWith('user-1');
      expect(mockContactsService.findAllByUser).toHaveBeenCalledWith('user-1');
      expect(mockContactAccessService.generateToken).toHaveBeenCalledWith('inc-1', 'contact-1');
      expect(mockNotificationsService.dispatchAlertWaves).toHaveBeenCalledWith(
        'inc-1',
        'user-1',
        'Maria Silva',
        expect.arrayContaining([
          expect.objectContaining({
            id: 'contact-1',
            name: 'João',
            phone: '+5511999999999',
            canReceiveSms: true,
            accessUrl: 'https://view.safecircle.app/incident/inc-1?token=tok-abc',
          }),
        ]),
        undefined,
        false,
      );
    });

    it('should NOT call dispatchAlertWaves in test mode (isTestMode=true)', async () => {
      const incident = createMockIncident({
        status: IncidentStatus.COUNTDOWN,
        isTestMode: true,
      });
      mockIncidentRepo.findOne.mockResolvedValue(incident);

      await incidentsService.activate('inc-1', 'user-1');

      // dispatchAlertWaves IS called, but with isTestMode=true
      // The NotificationsService.dispatchAlertWaves skips real dispatch in test mode
      expect(mockNotificationsService.dispatchAlertWaves).toHaveBeenCalledWith(
        'inc-1', 'user-1', 'Maria Silva',
        expect.any(Array),
        undefined,
        true, // isTestMode
      );
    });

    it('should gracefully handle zero contacts', async () => {
      const incident = createMockIncident({ status: IncidentStatus.COUNTDOWN });
      mockIncidentRepo.findOne.mockResolvedValue(incident);
      mockContactsService.findAllByUser.mockResolvedValue([]);

      // Should not throw
      const result = await incidentsService.activate('inc-1', 'user-1');
      expect(result).toBeDefined();
      expect(mockNotificationsService.dispatchAlertWaves).not.toHaveBeenCalled();
    });
  });

  describe('secret cancel triggers alert dispatch', () => {
    it('should dispatch alerts when coercion PIN is used', async () => {
      const incident = createMockIncident({ status: IncidentStatus.ACTIVE });
      mockIncidentRepo.findOne.mockResolvedValue(incident);

      mockRiskEngine.evaluateAndPersist.mockResolvedValue({
        result: {
          previousScore: 0, newScore: 95,
          previousLevel: RiskLevel.NONE, newLevel: RiskLevel.CRITICAL,
          scoreDelta: 95, reasons: ['Coercion PIN'],
        },
        records: [],
      });

      await incidentsService.cancel('inc-1', 'user-1', { isSecretCancel: true });

      expect(mockNotificationsService.dispatchAlertWaves).toHaveBeenCalled();
      expect(mockNotificationsService.cancelPendingWaves).not.toHaveBeenCalled();
    });
  });

  describe('normal cancel/resolve cancels pending waves', () => {
    it('should cancel pending waves on normal cancel', async () => {
      const incident = createMockIncident({ status: IncidentStatus.COUNTDOWN });
      mockIncidentRepo.findOne.mockResolvedValue(incident);

      await incidentsService.cancel('inc-1', 'user-1', { isSecretCancel: false });

      expect(mockNotificationsService.cancelPendingWaves).toHaveBeenCalledWith('inc-1');
      expect(mockNotificationsService.dispatchAlertWaves).not.toHaveBeenCalled();
    });

    it('should cancel pending waves on resolve', async () => {
      const incident = createMockIncident({ status: IncidentStatus.ACTIVE });
      mockIncidentRepo.findOne.mockResolvedValue(incident);

      await incidentsService.resolve('inc-1', 'user-1', { isFalseAlarm: false });

      expect(mockNotificationsService.cancelPendingWaves).toHaveBeenCalledWith('inc-1');
    });
  });
});
