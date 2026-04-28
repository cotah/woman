import { Test, TestingModule } from '@nestjs/testing';
import { getRepositoryToken } from '@nestjs/typeorm';
import { getQueueToken } from '@nestjs/bullmq';
import { NotificationsService, TrustedContactInfo } from '../../src/modules/notifications/notifications.service';
import { AlertDelivery } from '../../src/modules/notifications/entities/alert-delivery.entity';
import { ContactResponse } from '../../src/modules/notifications/entities/contact-response.entity';
import { SmsProvider } from '../../src/modules/notifications/providers/sms.provider';
import { PushProvider } from '../../src/modules/notifications/providers/push.provider';
import { VoiceProvider } from '../../src/modules/notifications/providers/voice.provider';

describe('Contact Notifications (Integration)', () => {
  let module: TestingModule;
  let service: NotificationsService;
  let mockDeliveryRepo: any;
  let mockResponseRepo: any;
  let mockAlertQueue: any;
  let mockSmsProvider: any;
  let mockPushProvider: any;
  let mockVoiceProvider: any;
  let deliveriesCreated: any[];

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

  beforeEach(async () => {
    deliveriesCreated = [];

    mockDeliveryRepo = {
      create: jest.fn((data) => {
        const delivery = { id: `del-${deliveriesCreated.length + 1}`, createdAt: new Date(), ...data };
        deliveriesCreated.push(delivery);
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

    module = await Test.createTestingModule({
      providers: [
        NotificationsService,
        { provide: getRepositoryToken(AlertDelivery), useValue: mockDeliveryRepo },
        { provide: getRepositoryToken(ContactResponse), useValue: mockResponseRepo },
        { provide: getQueueToken('alert-dispatch'), useValue: mockAlertQueue },
        { provide: SmsProvider, useValue: mockSmsProvider },
        { provide: PushProvider, useValue: mockPushProvider },
        { provide: VoiceProvider, useValue: mockVoiceProvider },
      ],
    }).compile();

    service = module.get(NotificationsService);
  });

  afterEach(async () => {
    await module.close();
  });

  describe('creating an active incident dispatches alerts', () => {
    it('should schedule all 3 wave jobs when dispatchAlertWaves is called', async () => {
      const contacts = [
        makeContact({ id: 'c1', priority: 1 }),
        makeContact({ id: 'c2', priority: 2 }),
      ];

      await service.dispatchAlertWaves('inc-1', 'user-1', 'Jane Doe', contacts);

      expect(mockAlertQueue.add).toHaveBeenCalledTimes(3);
      const jobNames = mockAlertQueue.add.mock.calls.map((c: any) => c[0]);
      expect(jobNames).toEqual(['dispatch-wave', 'dispatch-wave', 'dispatch-wave']);
    });

    it('should include all contacts in the wave payload', async () => {
      const contacts = [
        makeContact({ id: 'c1', priority: 1, name: 'Alice' }),
        makeContact({ id: 'c2', priority: 3, name: 'Bob' }),
      ];

      await service.dispatchAlertWaves('inc-1', 'user-1', 'Jane', contacts);

      const wave1Payload = mockAlertQueue.add.mock.calls[0][1];
      expect(wave1Payload.contacts).toHaveLength(2);
    });
  });

  describe('contacts receive correct channels based on permissions', () => {
    it('should send push and SMS to contacts with both enabled', async () => {
      const contacts = [
        makeContact({ id: 'c1', priority: 1, canReceiveSms: true, canReceivePush: true }),
      ];

      await service.executeWave({
        incidentId: 'inc-1',
        userId: 'user-1',
        userName: 'Jane',
        wave: 1,
        maxPriority: 2,
        channels: ['push', 'sms'],
        contacts,
      });

      // Should have created 2 deliveries: one push, one SMS
      expect(deliveriesCreated).toHaveLength(2);
      const channels = deliveriesCreated.map((d) => d.channel);
      expect(channels).toContain('push');
      expect(channels).toContain('sms');

      // Both providers should have been called
      expect(mockPushProvider.send).toHaveBeenCalled();
      expect(mockSmsProvider.send).toHaveBeenCalled();
    });

    it('should only send push to a contact without a phone number', async () => {
      const contacts = [
        makeContact({ id: 'c1', priority: 1, phone: undefined, canReceiveSms: false }),
      ];

      await service.executeWave({
        incidentId: 'inc-1',
        userId: 'user-1',
        userName: 'Jane',
        wave: 1,
        maxPriority: 2,
        channels: ['push', 'sms'],
        contacts,
      });

      expect(deliveriesCreated).toHaveLength(1);
      expect(deliveriesCreated[0].channel).toBe('push');
      expect(mockSmsProvider.send).not.toHaveBeenCalled();
    });

    it('should send voice_call in wave 2 to eligible contacts', async () => {
      const contacts = [
        makeContact({ id: 'c1', priority: 1, canReceiveVoiceCall: true }),
      ];

      await service.executeWave({
        incidentId: 'inc-1',
        userId: 'user-1',
        userName: 'Jane',
        wave: 2,
        maxPriority: 4,
        channels: ['push', 'sms', 'voice_call'],
        contacts,
      });

      const voiceDeliveries = deliveriesCreated.filter((d) => d.channel === 'voice_call');
      expect(voiceDeliveries).toHaveLength(1);
      expect(mockVoiceProvider.send).toHaveBeenCalled();
    });
  });

  describe('response tracking', () => {
    it('should record a contact response', async () => {
      await service.recordContactResponse('inc-1', 'c1', {
        responseType: 'trying_to_reach',
        note: 'On my way to help',
      });

      expect(mockResponseRepo.create).toHaveBeenCalledWith(
        expect.objectContaining({
          incidentId: 'inc-1',
          contactId: 'c1',
          responseType: 'trying_to_reach',
          note: 'On my way to help',
        }),
      );
      expect(mockResponseRepo.save).toHaveBeenCalled();
    });

    it('should create a contact_responded incident event', async () => {
      await service.recordContactResponse('inc-1', 'c1', {
        responseType: 'going_to_location',
      });

      expect(mockDeliveryRepo.manager.query).toHaveBeenCalledWith(
        expect.stringContaining('INSERT INTO incident_events'),
        expect.arrayContaining(['inc-1', 'contact_responded']),
      );
    });

    it('should retrieve all responses for an incident', async () => {
      const mockResponses = [
        { id: 'r1', incidentId: 'inc-1', contactId: 'c1', responseType: 'trying_to_reach' },
        { id: 'r2', incidentId: 'inc-1', contactId: 'c2', responseType: 'calling_authorities' },
      ];
      mockResponseRepo.find.mockResolvedValue(mockResponses);

      const responses = await service.getResponsesByIncident('inc-1');

      expect(responses).toHaveLength(2);
      expect(mockResponseRepo.find).toHaveBeenCalledWith(
        expect.objectContaining({
          where: { incidentId: 'inc-1' },
        }),
      );
    });
  });

  describe('delivery tracking', () => {
    it('should mark delivery as sending with externalId on success', async () => {
      const contacts = [makeContact({ id: 'c1', priority: 1, canReceivePush: false, canReceiveVoiceCall: false })];

      await service.executeWave({
        incidentId: 'inc-1',
        userId: 'user-1',
        userName: 'Jane',
        wave: 1,
        maxPriority: 2,
        channels: ['sms'],
        contacts,
      });

      expect(mockDeliveryRepo.update).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          status: 'sending',
          externalId: 'sms-ext-1',
        }),
      );
    });

    it('should retrieve all deliveries for an incident', async () => {
      const mockDeliveries = [
        { id: 'del-1', incidentId: 'inc-1', channel: 'push', wave: 1 },
        { id: 'del-2', incidentId: 'inc-1', channel: 'sms', wave: 1 },
      ];
      mockDeliveryRepo.find.mockResolvedValue(mockDeliveries);

      const deliveries = await service.getDeliveriesByIncident('inc-1');

      expect(deliveries).toHaveLength(2);
    });
  });
});
