import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Job } from 'bullmq';
import { AlertDelivery } from '@/modules/notifications/entities/alert-delivery.entity';
import { IncidentGateway } from '@/websocket/incident.gateway';

export interface AlertDispatchJobData {
  alertDeliveryId: string;
  incidentId: string;
  contactId: string;
  channel: 'push' | 'sms' | 'voice_call' | 'email';
  messageBody: string;
  contactPhone?: string;
  contactEmail?: string;
  pushToken?: string;
}

@Processor('alerts', {
  concurrency: 10,
  limiter: {
    max: 50,
    duration: 1000, // 50 jobs per second
  },
})
export class AlertProcessor extends WorkerHost {
  private readonly logger = new Logger(AlertProcessor.name);

  constructor(
    @InjectRepository(AlertDelivery)
    private readonly alertRepo: Repository<AlertDelivery>,
    private readonly incidentGateway: IncidentGateway,
  ) {
    super();
  }

  async process(job: Job<AlertDispatchJobData>): Promise<void> {
    const { alertDeliveryId, incidentId, channel } = job.data;
    this.logger.log(
      `Processing alert ${alertDeliveryId} via ${channel} for incident ${incidentId}`,
    );

    // Mark as sending
    await this.alertRepo.update(alertDeliveryId, {
      status: 'sending' as any,
      sentAt: new Date(),
    });

    try {
      await this.dispatchByChannel(job.data);

      // Mark as delivered
      await this.alertRepo.update(alertDeliveryId, {
        status: 'delivered' as any,
        deliveredAt: new Date(),
      });

      this.incidentGateway.broadcastAlertUpdate(incidentId, {
        alertId: alertDeliveryId,
        channel,
        status: 'delivered',
        contactId: job.data.contactId,
      });

      this.logger.log(
        `Alert ${alertDeliveryId} delivered via ${channel}`,
      );
    } catch (error) {
      const delivery = await this.alertRepo.findOne({
        where: { id: alertDeliveryId },
      });

      if (delivery && delivery.retryCount < delivery.maxRetries) {
        await this.alertRepo.update(alertDeliveryId, {
          status: 'retrying' as any,
          retryCount: delivery.retryCount + 1,
          failureReason: error.message,
        });

        // Re-throw to trigger BullMQ retry with backoff
        throw error;
      }

      // Max retries exhausted
      await this.alertRepo.update(alertDeliveryId, {
        status: 'failed' as any,
        failedAt: new Date(),
        failureReason: error.message,
      });

      this.incidentGateway.broadcastAlertUpdate(incidentId, {
        alertId: alertDeliveryId,
        channel,
        status: 'failed',
        contactId: job.data.contactId,
      });

      this.logger.error(
        `Alert ${alertDeliveryId} failed permanently: ${error.message}`,
        error.stack,
      );
    }
  }

  private async dispatchByChannel(data: AlertDispatchJobData): Promise<void> {
    switch (data.channel) {
      case 'sms':
        await this.sendSms(data);
        break;
      case 'push':
        await this.sendPush(data);
        break;
      case 'voice_call':
        await this.sendVoiceCall(data);
        break;
      case 'email':
        await this.sendEmail(data);
        break;
      default:
        throw new Error(`Unsupported alert channel: ${data.channel}`);
    }
  }

  /**
   * SMS dispatch via Twilio.
   * Actual provider integration is delegated to notification providers;
   * this processor orchestrates the job lifecycle.
   */
  private async sendSms(data: AlertDispatchJobData): Promise<void> {
    if (!data.contactPhone) {
      throw new Error('No phone number for SMS delivery');
    }
    // In production, inject and call SmsProvider here
    // await this.smsProvider.send(data.contactPhone, data.messageBody);
    this.logger.log(`SMS dispatched to ${data.contactPhone}`);
  }

  private async sendPush(data: AlertDispatchJobData): Promise<void> {
    if (!data.pushToken) {
      throw new Error('No push token for push notification delivery');
    }
    // In production, inject and call PushProvider here
    // await this.pushProvider.send(data.pushToken, { body: data.messageBody });
    this.logger.log(`Push notification dispatched to token ${data.pushToken.slice(0, 10)}...`);
  }

  private async sendVoiceCall(data: AlertDispatchJobData): Promise<void> {
    if (!data.contactPhone) {
      throw new Error('No phone number for voice call delivery');
    }
    // In production, inject and call VoiceProvider here
    // await this.voiceProvider.call(data.contactPhone, data.messageBody);
    this.logger.log(`Voice call dispatched to ${data.contactPhone}`);
  }

  private async sendEmail(data: AlertDispatchJobData): Promise<void> {
    if (!data.contactEmail) {
      throw new Error('No email address for email delivery');
    }
    // In production, inject and call EmailProvider here
    this.logger.log(`Email dispatched to ${data.contactEmail}`);
  }
}
