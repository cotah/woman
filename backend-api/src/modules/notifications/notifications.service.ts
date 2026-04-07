import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, In } from 'typeorm';
import { InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';
import { AlertDelivery, AlertChannel } from './entities/alert-delivery.entity';
import { ContactResponse } from './entities/contact-response.entity';
import { SmsProvider } from './providers/sms.provider';
import { PushProvider } from './providers/push.provider';
import { VoiceProvider } from './providers/voice.provider';
import {
  NotificationProvider,
  NotificationPayload,
  NotificationRecipient,
} from './providers/notification-provider.interface';
import { ContactRespondDto } from './dto/contact-respond.dto';

/** Wave configuration: which priorities and channels per wave. */
interface WaveConfig {
  wave: number;
  maxPriority: number;
  channels: AlertChannel[];
  delayMs: number;
}

const DEFAULT_WAVE_CONFIG: WaveConfig[] = [
  { wave: 1, maxPriority: 2, channels: ['push', 'sms'], delayMs: 0 },
  { wave: 2, maxPriority: 4, channels: ['push', 'sms', 'voice_call'], delayMs: 60_000 },
  { wave: 3, maxPriority: 999, channels: ['push', 'sms', 'voice_call', 'email'], delayMs: 120_000 },
];

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);
  private readonly providerMap: Map<AlertChannel, NotificationProvider>;

  constructor(
    @InjectRepository(AlertDelivery)
    private readonly deliveryRepo: Repository<AlertDelivery>,
    @InjectRepository(ContactResponse)
    private readonly responseRepo: Repository<ContactResponse>,
    @InjectQueue('alert-dispatch')
    private readonly alertQueue: Queue,
    private readonly smsProvider: SmsProvider,
    private readonly pushProvider: PushProvider,
    private readonly voiceProvider: VoiceProvider,
  ) {
    this.providerMap = new Map<AlertChannel, NotificationProvider>([
      ['sms', this.smsProvider],
      ['push', this.pushProvider],
      ['voice_call', this.voiceProvider],
    ]);
  }

  // ------------------------------------------------------------------
  // Public API
  // ------------------------------------------------------------------

  /**
   * Schedule all three waves for an incident.
   * Called by the incident service when an incident is activated.
   */
  async dispatchAlertWaves(
    incidentId: string,
    userId: string,
    userName: string,
    contacts: TrustedContactInfo[],
    waveConfig: WaveConfig[] = DEFAULT_WAVE_CONFIG,
    isTestMode = false,
  ): Promise<void> {
    if (isTestMode) {
      this.logger.log(
        `[TEST-MODE] Skipping real alert dispatch for incident ${incidentId}. ` +
        `No SMS/push/voice will be sent. This is a simulated alert.`,
      );
      return;
    }

    // Check if providers are in dry-run mode and log clearly.
    const hasSms = this.providerMap.has('sms');
    const hasPush = this.providerMap.has('push');
    this.logger.log(
      `[ALERT-DISPATCH] Scheduling ${waveConfig.length} waves for incident ${incidentId} | ` +
      `contacts=${contacts.length} | SMS provider=${hasSms ? 'configured' : 'MISSING'} | ` +
      `Push provider=${hasPush ? 'configured' : 'MISSING'}`,
    );

    for (const wave of waveConfig) {
      await this.alertQueue.add(
        'dispatch-wave',
        {
          incidentId,
          userId,
          userName,
          wave: wave.wave,
          maxPriority: wave.maxPriority,
          channels: wave.channels,
          contacts,
        },
        {
          delay: wave.delayMs,
          attempts: 1,
          removeOnComplete: true,
          jobId: `wave-${incidentId}-${wave.wave}`,
        },
      );
    }
  }

  /**
   * Cancel pending waves (e.g. when incident is resolved/cancelled).
   */
  async cancelPendingWaves(incidentId: string): Promise<void> {
    for (const wave of [1, 2, 3]) {
      const jobId = `wave-${incidentId}-${wave}`;
      const job = await this.alertQueue.getJob(jobId);
      if (job && (await job.isDelayed())) {
        await job.remove();
        this.logger.log(`Cancelled wave ${wave} for incident ${incidentId}`);
      }
    }

    // Mark queued deliveries as failed/cancelled
    await this.deliveryRepo.update(
      { incidentId, status: In(['queued']) as any },
      { status: 'failed', failureReason: 'Incident resolved before dispatch', failedAt: new Date() },
    );
  }

  /**
   * Execute a single wave. Called by the BullMQ worker/processor.
   */
  async executeWave(payload: {
    incidentId: string;
    userId: string;
    userName: string;
    wave: number;
    maxPriority: number;
    channels: AlertChannel[];
    contacts: TrustedContactInfo[];
  }): Promise<void> {
    const { incidentId, userName, wave, maxPriority, channels, contacts } = payload;

    this.logger.log(
      `Executing wave ${wave} for incident ${incidentId} | ` +
        `channels=${channels.join(',')} | maxPriority=${maxPriority}`,
    );

    // Filter contacts by priority
    const eligibleContacts = contacts.filter((c) => c.priority <= maxPriority);

    // Create incident event for escalation wave
    await this.createIncidentEvent(incidentId, 'escalation_wave', {
      wave,
      contactCount: eligibleContacts.length,
      channels,
    });

    // Dispatch to each contact on each eligible channel
    const deliveryPromises: Promise<void>[] = [];

    for (const contact of eligibleContacts) {
      for (const channel of channels) {
        if (!this.isContactEligibleForChannel(contact, channel)) {
          continue;
        }

        // Skip if we already delivered to this contact on this channel in a previous wave
        const existing = await this.deliveryRepo.findOne({
          where: {
            incidentId,
            contactId: contact.id,
            channel,
            status: In(['delivered', 'sending']) as any,
          },
        });
        if (existing) continue;

        deliveryPromises.push(
          this.dispatchSingleDelivery(incidentId, contact, channel, wave, userName),
        );
      }
    }

    await Promise.allSettled(deliveryPromises);

    this.logger.log(`Wave ${wave} complete for incident ${incidentId}`);
  }

  /**
   * Retry a failed delivery. Called by retry scheduler or manually.
   */
  async retryDelivery(deliveryId: string): Promise<void> {
    const delivery = await this.deliveryRepo.findOneOrFail({
      where: { id: deliveryId },
    });

    if (delivery.retryCount >= delivery.maxRetries) {
      this.logger.warn(
        `Delivery ${deliveryId} exceeded max retries (${delivery.maxRetries})`,
      );
      await this.createIncidentEvent(delivery.incidentId, 'alert_failed', {
        deliveryId,
        channel: delivery.channel,
        contactId: delivery.contactId,
        retryCount: delivery.retryCount,
        reason: 'Max retries exceeded',
      });
      return;
    }

    await this.deliveryRepo.update(deliveryId, {
      status: 'retrying',
      retryCount: delivery.retryCount + 1,
    });

    await this.alertQueue.add(
      'retry-delivery',
      { deliveryId },
      {
        delay: this.getRetryDelay(delivery.retryCount + 1),
        attempts: 1,
        removeOnComplete: true,
      },
    );
  }

  /**
   * Execute a retry for a single delivery.
   */
  async executeRetry(deliveryId: string): Promise<void> {
    const delivery = await this.deliveryRepo.findOneOrFail({
      where: { id: deliveryId },
    });

    const provider = this.providerMap.get(delivery.channel);
    if (!provider) {
      await this.markDeliveryFailed(delivery, `No provider for channel: ${delivery.channel}`);
      return;
    }

    // We need to reconstruct recipient and payload from the delivery context.
    // In production this would be fetched from the contacts table.
    // The delivery record stores enough context via message_body.
    try {
      const result = await provider.send(
        { contactId: delivery.contactId, name: '', phone: '', locale: 'en' },
        {
          incidentId: delivery.incidentId,
          userName: '',
          message: delivery.messageBody || '',
        },
      );

      if (result.success) {
        await this.deliveryRepo.update(deliveryId, {
          status: 'sending',
          externalId: result.externalId || null,
          sentAt: new Date(),
        });
      } else {
        await this.markDeliveryFailed(delivery, result.error || 'Unknown error');
        if (delivery.retryCount < delivery.maxRetries) {
          await this.retryDelivery(deliveryId);
        }
      }
    } catch (error) {
      await this.markDeliveryFailed(delivery, error.message);
      if (delivery.retryCount < delivery.maxRetries) {
        await this.retryDelivery(deliveryId);
      }
    }
  }

  /**
   * Record a contact response to an incident.
   */
  async recordContactResponse(
    incidentId: string,
    contactId: string,
    dto: ContactRespondDto,
  ): Promise<ContactResponse> {
    const response = this.responseRepo.create({
      incidentId,
      contactId,
      responseType: dto.responseType as any,
      note: dto.note || null,
      respondedAt: new Date(),
    });

    const saved = await this.responseRepo.save(response);

    await this.createIncidentEvent(incidentId, 'contact_responded', {
      contactId,
      responseType: dto.responseType,
      note: dto.note,
    });

    this.logger.log(
      `Contact ${contactId} responded to incident ${incidentId}: ${dto.responseType}`,
    );

    return saved;
  }

  /**
   * Get all deliveries for an incident.
   */
  async getDeliveriesByIncident(incidentId: string): Promise<AlertDelivery[]> {
    return this.deliveryRepo.find({
      where: { incidentId },
      order: { wave: 'ASC', createdAt: 'ASC' },
    });
  }

  /**
   * Get all responses for an incident.
   */
  async getResponsesByIncident(incidentId: string): Promise<ContactResponse[]> {
    return this.responseRepo.find({
      where: { incidentId },
      order: { respondedAt: 'ASC' },
    });
  }

  // ------------------------------------------------------------------
  // Private helpers
  // ------------------------------------------------------------------

  private async dispatchSingleDelivery(
    incidentId: string,
    contact: TrustedContactInfo,
    channel: AlertChannel,
    wave: number,
    userName: string,
  ): Promise<void> {
    const messageBody = `Security alert. A possible emergency situation has been triggered for ${userName}. Immediate verification recommended.`;

    // Create the delivery record
    const delivery = this.deliveryRepo.create({
      incidentId,
      contactId: contact.id,
      channel,
      status: 'queued',
      wave,
      messageBody,
      retryCount: 0,
      maxRetries: 3,
    });
    const saved = await this.deliveryRepo.save(delivery);

    const provider = this.providerMap.get(channel);
    if (!provider) {
      await this.markDeliveryFailed(saved, `No provider for channel: ${channel}`);
      return;
    }

    const recipient: NotificationRecipient = {
      contactId: contact.id,
      name: contact.name,
      phone: contact.phone,
      email: contact.email,
      pushToken: contact.pushToken,
      locale: contact.locale || 'en',
    };

    const payload: NotificationPayload = {
      incidentId,
      userName,
      message: messageBody,
      accessUrl: contact.accessUrl,
      latitude: contact.lastLatitude,
      longitude: contact.lastLongitude,
    };

    try {
      const result = await provider.send(recipient, payload);

      if (result.success) {
        await this.deliveryRepo.update(saved.id, {
          status: 'sending',
          externalId: result.externalId || null,
          sentAt: new Date(),
        });

        await this.createIncidentEvent(incidentId, 'alert_dispatched', {
          deliveryId: saved.id,
          channel,
          contactId: contact.id,
          contactName: contact.name,
          wave,
          externalId: result.externalId,
        });
      } else {
        await this.markDeliveryFailed(saved, result.error || 'Send returned failure');
        if (saved.retryCount < saved.maxRetries) {
          await this.retryDelivery(saved.id);
        }
      }
    } catch (error) {
      this.logger.error(
        `Delivery failed for ${channel} to contact ${contact.id}: ${error.message}`,
        error.stack,
      );
      await this.markDeliveryFailed(saved, error.message);
      if (saved.retryCount < saved.maxRetries) {
        await this.retryDelivery(saved.id);
      }
    }
  }

  private async markDeliveryFailed(
    delivery: AlertDelivery,
    reason: string,
  ): Promise<void> {
    await this.deliveryRepo.update(delivery.id, {
      status: 'failed',
      failedAt: new Date(),
      failureReason: reason,
    });

    await this.createIncidentEvent(delivery.incidentId, 'alert_failed', {
      deliveryId: delivery.id,
      channel: delivery.channel,
      contactId: delivery.contactId,
      reason,
      retryCount: delivery.retryCount,
    });
  }

  private isContactEligibleForChannel(
    contact: TrustedContactInfo,
    channel: AlertChannel,
  ): boolean {
    switch (channel) {
      case 'sms':
        return contact.canReceiveSms && !!contact.phone;
      case 'push':
        return contact.canReceivePush && !!contact.pushToken;
      case 'voice_call':
        return contact.canReceiveVoiceCall && !!contact.phone;
      case 'email':
        return !!contact.email;
      default:
        return false;
    }
  }

  private getRetryDelay(retryCount: number): number {
    // Exponential backoff: 10s, 30s, 90s
    return Math.min(10_000 * Math.pow(3, retryCount - 1), 300_000);
  }

  private async createIncidentEvent(
    incidentId: string,
    type: string,
    payload: Record<string, any>,
  ): Promise<void> {
    // Use a raw query to insert into incident_events to avoid circular module deps.
    // In a full setup this would go through an EventEmitter or dedicated timeline service.
    try {
      await this.deliveryRepo.manager.query(
        `INSERT INTO incident_events (incident_id, type, payload, source, is_internal)
         VALUES ($1, $2, $3, 'notification_service', false)`,
        [incidentId, type, JSON.stringify(payload)],
      );
    } catch (error) {
      this.logger.error(
        `Failed to create incident event (${type}): ${error.message}`,
      );
    }
  }
}

/**
 * Trusted contact info passed to the notification service.
 * Combines data from trusted_contacts + user_devices + contact_access_tokens.
 */
export interface TrustedContactInfo {
  id: string;
  name: string;
  phone?: string;
  email?: string;
  pushToken?: string;
  priority: number;
  locale: string;
  canReceiveSms: boolean;
  canReceivePush: boolean;
  canReceiveVoiceCall: boolean;
  accessUrl?: string;
  lastLatitude?: number;
  lastLongitude?: number;
}
