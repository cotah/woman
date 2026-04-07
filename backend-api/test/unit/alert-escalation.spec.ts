import { NotificationsService, TrustedContactInfo } from '../../src/modules/notifications/notifications.service';

describe('NotificationsService - Alert Escalation Waves', () => {
  let service: NotificationsService;
  let mockDeliveryRepo: any;
  let mockResponseRepo: any;
  let mockAlertQueue: any;
  let mockSmsProvider: any;
  let mockPushProvider: any;
  let mockVoiceProvider: any;

  const makeContact = (overrides: Partial<TrustedContactInfo> = {}): TrustedContactInfo => ({
    id: 'contact-1',
    name: 'Alice',
    phone: '+1234567890',
    email: 'alice@example.com',
    pushToken: 'push-token-1',
    priority: 1,
    locale: 'en',
    canReceiveSms: true,
    canReceivePush: true,
    canReceiveVoiceCall: true,
    ...overrides,
  });

  const contacts: TrustedContactInfo[] = [
    makeContact({ id: 'c1', name: 'Priority1', priority: 1 }),
    makeContact({ id: 'c2', name: 'Priority2', priority: 2 }),
    makeContact({ id: 'c3', name: 'Priority3', priority: 3 }),
    makeContact({ id: 'c4', name: 'Priority4', priority: 4 }),
    makeContact({ id: 'c5', name: 'Priority5', priority: 5 }),
    makeContact({ id: 'c6', name: 'Priority10', priority: 10 }),
  ];

  beforeEach(() => {
    mockDeliveryRepo = {
      create: jest.fn((data) => ({ id: `del-${Math.random()}`, ...data })),
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
      create: jest.fn((data) => data),
      save: jest.fn((data) => Promise.resolve(data)),
      find: jest.fn().mockResolvedValue([]),
    };

    mockAlertQueue = {
      add: jest.fn().mockResolvedValue({}),
      getJob: jest.fn().mockResolvedValue(null),
    };

    mockSmsProvider = {
      channel: 'sms',
      send: jest.fn().mockResolvedValue({ success: true, externalId: 'sms-ext-1' }),
      getStatus: jest.fn(),
    };

    mockPushProvider = {
      channel: 'push',
      send: jest.fn().mockResolvedValue({ success: true, externalId: 'push-ext-1' }),
      getStatus: jest.fn(),
    };

    mockVoiceProvider = {
      channel: 'voice_call',
      send: jest.fn().mockResolvedValue({ success: true, externalId: 'voice-ext-1' }),
      getStatus: jest.fn(),
    };

    service = new NotificationsService(
      mockDeliveryRepo,
      mockResponseRepo,
      mockAlertQueue,
      mockSmsProvider,
      mockPushProvider,
      mockVoiceProvider,
    );
  });

  describe('dispatchAlertWaves - wave scheduling', () => {
    it('should schedule 3 waves in the alert queue', async () => {
      await service.dispatchAlertWaves('inc-1', 'user-1', 'Jane', contacts);

      expect(mockAlertQueue.add).toHaveBeenCalledTimes(3);
    });

    it('wave 1 should target maxPriority 2 with push + sms channels', async () => {
      await service.dispatchAlertWaves('inc-1', 'user-1', 'Jane', contacts);

      const wave1Call = mockAlertQueue.add.mock.calls[0];
      expect(wave1Call[0]).toBe('dispatch-wave');
      expect(wave1Call[1].wave).toBe(1);
      expect(wave1Call[1].maxPriority).toBe(2);
      expect(wave1Call[1].channels).toEqual(['push', 'sms']);
    });

    it('wave 2 should target maxPriority 4 with push + sms + voice_call channels', async () => {
      await service.dispatchAlertWaves('inc-1', 'user-1', 'Jane', contacts);

      const wave2Call = mockAlertQueue.add.mock.calls[1];
      expect(wave2Call[1].wave).toBe(2);
      expect(wave2Call[1].maxPriority).toBe(4);
      expect(wave2Call[1].channels).toContain('voice_call');
      expect(wave2Call[1].channels).toContain('push');
      expect(wave2Call[1].channels).toContain('sms');
    });

    it('wave 3 should reach all contacts (maxPriority 999)', async () => {
      await service.dispatchAlertWaves('inc-1', 'user-1', 'Jane', contacts);

      const wave3Call = mockAlertQueue.add.mock.calls[2];
      expect(wave3Call[1].wave).toBe(3);
      expect(wave3Call[1].maxPriority).toBe(999);
      expect(wave3Call[1].channels).toEqual(['push', 'sms', 'voice_call', 'email']);
    });

    it('wave 1 should have no delay, wave 2 should have 60s delay, wave 3 should have 120s delay', async () => {
      await service.dispatchAlertWaves('inc-1', 'user-1', 'Jane', contacts);

      expect(mockAlertQueue.add.mock.calls[0][2].delay).toBe(0);
      expect(mockAlertQueue.add.mock.calls[1][2].delay).toBe(60_000);
      expect(mockAlertQueue.add.mock.calls[2][2].delay).toBe(120_000);
    });
  });

  describe('executeWave - contact filtering by priority', () => {
    it('wave 1 should only dispatch to priority 1-2 contacts', async () => {
      await service.executeWave({
        incidentId: 'inc-1',
        userId: 'user-1',
        userName: 'Jane',
        wave: 1,
        maxPriority: 2,
        channels: ['push', 'sms'],
        contacts,
      });

      // Should create deliveries only for priority 1 and 2 contacts
      const createCalls = mockDeliveryRepo.create.mock.calls;
      const contactIds = createCalls.map((c: any) => c[0].contactId);
      expect(contactIds).toContain('c1');
      expect(contactIds).toContain('c2');
      expect(contactIds).not.toContain('c3');
      expect(contactIds).not.toContain('c4');
      expect(contactIds).not.toContain('c5');
      expect(contactIds).not.toContain('c6');
    });

    it('wave 2 should dispatch to priority 1-4 contacts', async () => {
      await service.executeWave({
        incidentId: 'inc-1',
        userId: 'user-1',
        userName: 'Jane',
        wave: 2,
        maxPriority: 4,
        channels: ['push', 'sms', 'voice_call'],
        contacts,
      });

      const createCalls = mockDeliveryRepo.create.mock.calls;
      const contactIds = [...new Set(createCalls.map((c: any) => c[0].contactId))];
      expect(contactIds).toContain('c1');
      expect(contactIds).toContain('c2');
      expect(contactIds).toContain('c3');
      expect(contactIds).toContain('c4');
      expect(contactIds).not.toContain('c5');
      expect(contactIds).not.toContain('c6');
    });

    it('wave 3 should dispatch to all contacts', async () => {
      await service.executeWave({
        incidentId: 'inc-1',
        userId: 'user-1',
        userName: 'Jane',
        wave: 3,
        maxPriority: 999,
        channels: ['push', 'sms', 'voice_call', 'email'],
        contacts,
      });

      const createCalls = mockDeliveryRepo.create.mock.calls;
      const contactIds = [...new Set(createCalls.map((c: any) => c[0].contactId))];
      expect(contactIds).toContain('c1');
      expect(contactIds).toContain('c5');
      expect(contactIds).toContain('c6');
    });
  });

  describe('executeWave - channel eligibility', () => {
    it('should skip SMS for contacts without a phone number', async () => {
      const noPhoneContacts = [
        makeContact({ id: 'cp1', priority: 1, phone: undefined, canReceiveSms: true }),
      ];

      await service.executeWave({
        incidentId: 'inc-1',
        userId: 'user-1',
        userName: 'Jane',
        wave: 1,
        maxPriority: 2,
        channels: ['sms'],
        contacts: noPhoneContacts,
      });

      expect(mockDeliveryRepo.create).not.toHaveBeenCalled();
    });

    it('should skip push for contacts without a push token', async () => {
      const noPushContacts = [
        makeContact({ id: 'cp1', priority: 1, pushToken: undefined, canReceivePush: true }),
      ];

      await service.executeWave({
        incidentId: 'inc-1',
        userId: 'user-1',
        userName: 'Jane',
        wave: 1,
        maxPriority: 2,
        channels: ['push'],
        contacts: noPushContacts,
      });

      expect(mockDeliveryRepo.create).not.toHaveBeenCalled();
    });

    it('should skip voice_call for contacts with canReceiveVoiceCall=false', async () => {
      const noVoiceContacts = [
        makeContact({ id: 'cp1', priority: 1, canReceiveVoiceCall: false }),
      ];

      await service.executeWave({
        incidentId: 'inc-1',
        userId: 'user-1',
        userName: 'Jane',
        wave: 2,
        maxPriority: 2,
        channels: ['voice_call'],
        contacts: noVoiceContacts,
      });

      expect(mockDeliveryRepo.create).not.toHaveBeenCalled();
    });
  });

  describe('failed deliveries and retries', () => {
    it('should schedule a retry when a delivery fails', async () => {
      const failedDelivery = {
        id: 'del-1',
        incidentId: 'inc-1',
        contactId: 'c1',
        channel: 'sms',
        status: 'failed',
        retryCount: 0,
        maxRetries: 3,
        messageBody: 'Alert message',
      };

      mockDeliveryRepo.findOneOrFail.mockResolvedValue(failedDelivery);

      await service.retryDelivery('del-1');

      expect(mockDeliveryRepo.update).toHaveBeenCalledWith('del-1', {
        status: 'retrying',
        retryCount: 1,
      });
      expect(mockAlertQueue.add).toHaveBeenCalledWith(
        'retry-delivery',
        { deliveryId: 'del-1' },
        expect.objectContaining({ delay: expect.any(Number) }),
      );
    });

    it('should not retry when maxRetries is exceeded', async () => {
      const exhaustedDelivery = {
        id: 'del-1',
        incidentId: 'inc-1',
        contactId: 'c1',
        channel: 'sms',
        status: 'failed',
        retryCount: 3,
        maxRetries: 3,
        messageBody: 'Alert message',
      };

      mockDeliveryRepo.findOneOrFail.mockResolvedValue(exhaustedDelivery);

      await service.retryDelivery('del-1');

      // Should NOT schedule a retry
      expect(mockAlertQueue.add).not.toHaveBeenCalled();
      // Should create an alert_failed event
      expect(mockDeliveryRepo.manager.query).toHaveBeenCalled();
    });

    it('should schedule retry when provider send fails during executeWave', async () => {
      mockSmsProvider.send.mockResolvedValue({ success: false, error: 'Network error' });

      const singleContact = [makeContact({ id: 'c1', priority: 1, canReceivePush: false })];
      mockDeliveryRepo.findOneOrFail.mockResolvedValue({
        id: 'del-mock',
        incidentId: 'inc-1',
        contactId: 'c1',
        channel: 'sms',
        status: 'failed',
        retryCount: 0,
        maxRetries: 3,
      });

      await service.executeWave({
        incidentId: 'inc-1',
        userId: 'user-1',
        userName: 'Jane',
        wave: 1,
        maxPriority: 2,
        channels: ['sms'],
        contacts: singleContact,
      });

      // A retry should be scheduled via the queue
      expect(mockAlertQueue.add).toHaveBeenCalled();
    });
  });

  describe('cancelPendingWaves', () => {
    it('should attempt to remove delayed jobs for all 3 waves', async () => {
      const mockJob = {
        isDelayed: jest.fn().mockResolvedValue(true),
        remove: jest.fn().mockResolvedValue(undefined),
      };
      mockAlertQueue.getJob.mockResolvedValue(mockJob);

      await service.cancelPendingWaves('inc-1');

      expect(mockAlertQueue.getJob).toHaveBeenCalledTimes(3);
      expect(mockJob.remove).toHaveBeenCalledTimes(3);
    });

    it('should mark queued deliveries as failed when cancelling', async () => {
      mockAlertQueue.getJob.mockResolvedValue(null);

      await service.cancelPendingWaves('inc-1');

      expect(mockDeliveryRepo.update).toHaveBeenCalledWith(
        expect.objectContaining({ incidentId: 'inc-1' }),
        expect.objectContaining({ status: 'failed', failureReason: expect.any(String) }),
      );
    });
  });

  describe('contact response recording', () => {
    it('should save a contact response and create an incident event', async () => {
      const response = await service.recordContactResponse('inc-1', 'c1', {
        responseType: 'trying_to_reach',
        note: 'On my way',
      });

      expect(mockResponseRepo.create).toHaveBeenCalledWith(
        expect.objectContaining({
          incidentId: 'inc-1',
          contactId: 'c1',
          responseType: 'trying_to_reach',
          note: 'On my way',
        }),
      );
      expect(mockResponseRepo.save).toHaveBeenCalled();
      expect(mockDeliveryRepo.manager.query).toHaveBeenCalled(); // incident event created
    });
  });
});
