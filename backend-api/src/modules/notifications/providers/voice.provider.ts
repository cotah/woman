import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  NotificationProvider,
  NotificationRecipient,
  NotificationPayload,
  SendResult,
  DeliveryStatus,
} from './notification-provider.interface';

@Injectable()
export class VoiceProvider implements NotificationProvider {
  readonly channel = 'voice_call' as const;
  private readonly logger = new Logger(VoiceProvider.name);
  private client: any;
  private readonly fromNumber: string;
  private readonly twimlBaseUrl: string;

  constructor(private readonly config: ConfigService) {
    const accountSid = this.config.get<string>('TWILIO_ACCOUNT_SID');
    const authToken = this.config.get<string>('TWILIO_AUTH_TOKEN');
    this.fromNumber = this.config.get<string>('TWILIO_VOICE_FROM_NUMBER', '');
    this.twimlBaseUrl = this.config.get<string>(
      'TWIML_BASE_URL',
      'https://api.safecircle.app/twiml',
    );

    if (accountSid && authToken) {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const twilio = require('twilio');
      this.client = twilio(accountSid, authToken);
    } else {
      this.logger.warn(
        'Twilio credentials not configured; voice provider will operate in dry-run mode',
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

    const twiml = this.buildTwiml(recipient, payload);

    if (!this.client) {
      this.logger.debug(
        `[DRY-RUN] Voice call to ${recipient.phone}`,
      );
      return { success: true, externalId: `dry-run-${Date.now()}` };
    }

    try {
      const call = await this.client.calls.create({
        twiml,
        from: this.fromNumber,
        to: recipient.phone,
        statusCallback: this.config.get<string>('TWILIO_VOICE_STATUS_CALLBACK_URL'),
        statusCallbackEvent: ['initiated', 'ringing', 'answered', 'completed'],
        machineDetection: 'DetectMessageEnd',
        timeout: 30,
      });

      this.logger.log(
        `Voice call initiated to ${recipient.phone} | SID: ${call.sid}`,
      );
      return { success: true, externalId: call.sid };
    } catch (error) {
      this.logger.error(
        `Voice call failed to ${recipient.phone}: ${error.message}`,
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
      const call = await this.client.calls(externalId).fetch();
      const statusMap: Record<string, DeliveryStatus['status']> = {
        queued: 'queued',
        ringing: 'sending',
        'in-progress': 'sending',
        completed: 'delivered',
        busy: 'failed',
        'no-answer': 'failed',
        canceled: 'failed',
        failed: 'failed',
      };

      return {
        externalId,
        status: statusMap[call.status] ?? 'queued',
        updatedAt: call.dateUpdated ? new Date(call.dateUpdated) : undefined,
        error:
          call.status === 'failed' || call.status === 'busy' || call.status === 'no-answer'
            ? `Call status: ${call.status}`
            : undefined,
      };
    } catch (error) {
      this.logger.error(
        `Failed to fetch call status for ${externalId}: ${error.message}`,
      );
      return { externalId, status: 'failed', error: error.message };
    }
  }

  private buildTwiml(
    recipient: NotificationRecipient,
    payload: NotificationPayload,
  ): string {
    const spokenMessage = `This is a SafeCircle security alert. A possible emergency situation has been triggered for ${payload.userName}. Immediate verification is recommended. Please check your text messages for a link to view more details. If you believe this person is in danger, please contact local authorities immediately.`;

    // Repeat the message twice for clarity
    return `
      <Response>
        <Say voice="Polly.Joanna" language="en-US">
          ${this.escapeXml(spokenMessage)}
        </Say>
        <Pause length="2"/>
        <Say voice="Polly.Joanna" language="en-US">
          Repeating. ${this.escapeXml(spokenMessage)}
        </Say>
        <Pause length="1"/>
        <Say voice="Polly.Joanna" language="en-US">
          Press any key to confirm you received this message.
        </Say>
        <Gather numDigits="1" timeout="10">
          <Say voice="Polly.Joanna" language="en-US">
            Press any key now.
          </Say>
        </Gather>
        <Say voice="Polly.Joanna" language="en-US">
          No input received. Goodbye.
        </Say>
      </Response>
    `.trim();
  }

  private escapeXml(text: string): string {
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&apos;');
  }
}
