import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Twilio } from 'twilio';
import {
  NotificationProvider,
  NotificationRecipient,
  NotificationPayload,
  SendResult,
  DeliveryStatus,
} from './notification-provider.interface';

@Injectable()
export class SmsProvider implements NotificationProvider {
  readonly channel = 'sms' as const;
  private readonly logger = new Logger(SmsProvider.name);
  private client?: Twilio;
  private readonly fromNumber: string;

  constructor(private readonly config: ConfigService) {
    const accountSid = this.config.get<string>('TWILIO_ACCOUNT_SID');
    const authToken = this.config.get<string>('TWILIO_AUTH_TOKEN');
    this.fromNumber = this.config.get<string>('TWILIO_FROM_NUMBER', '');

    if (accountSid && authToken) {
      const twilio = require('twilio');
      this.client = twilio(accountSid, authToken);
    } else {
      this.logger.warn(
        'Twilio credentials not configured; SMS provider will operate in dry-run mode',
      );
    }
  }

  async send(
    recipient: NotificationRecipient,
    payload: NotificationPayload,
  ): Promise<SendResult> {
    if (!recipient.phone) {
      return { success: false, error: 'Recipient has no phone number' };
    }

    const body = this.buildMessage(recipient, payload);

    if (!this.client) {
      this.logger.debug(
        `[DRY-RUN] SMS to ${recipient.phone}: ${body}`,
      );
      return { success: true, externalId: `dry-run-${Date.now()}` };
    }

    try {
      const message = await this.client.messages.create({
        body,
        from: this.fromNumber,
        to: recipient.phone,
        statusCallback: this.config.get<string>('TWILIO_STATUS_CALLBACK_URL'),
      });

      this.logger.log(
        `SMS sent to ${recipient.phone} | SID: ${message.sid}`,
      );
      return { success: true, externalId: message.sid };
    } catch (error) {
      this.logger.error(
        `SMS delivery failed to ${recipient.phone}: ${error.message}`,
        error.stack,
      );
      return { success: false, error: error.message };
    }
  }

  async getStatus(externalId: string): Promise<DeliveryStatus> {
    if (!this.client || externalId.startsWith('dry-run-')) {
      return { externalId, status: 'delivered' };
    }

    try {
      const message = await this.client.messages(externalId).fetch();
      const statusMap: Record<string, DeliveryStatus['status']> = {
        queued: 'queued',
        sending: 'sending',
        sent: 'sending',
        delivered: 'delivered',
        undelivered: 'failed',
        failed: 'failed',
      };

      return {
        externalId,
        status: statusMap[message.status] ?? 'queued',
        updatedAt: message.dateUpdated ? new Date(message.dateUpdated) : undefined,
        error: message.errorMessage || undefined,
      };
    } catch (error) {
      this.logger.error(
        `Failed to fetch SMS status for ${externalId}: ${error.message}`,
      );
      return { externalId, status: 'failed', error: error.message };
    }
  }

  private buildMessage(
    recipient: NotificationRecipient,
    payload: NotificationPayload,
  ): string {
    const lines = [
      `Security alert. A possible emergency situation has been triggered for ${payload.userName}. Immediate verification recommended.`,
    ];

    if (payload.accessUrl) {
      lines.push(`View details: ${payload.accessUrl}`);
    }

    if (payload.latitude != null && payload.longitude != null) {
      lines.push(
        `Last known location: https://maps.google.com/?q=${payload.latitude},${payload.longitude}`,
      );
    }

    return lines.join('\n');
  }
}
