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
export class PushProvider implements NotificationProvider {
  readonly channel = 'push' as const;
  private readonly logger = new Logger(PushProvider.name);
  private messaging: any;

  constructor(private readonly config: ConfigService) {
    this.initializeFirebase();
  }

  private initializeFirebase(): void {
    try {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      const admin = require('firebase-admin');

      const projectId = this.config.get<string>('FIREBASE_PROJECT_ID');
      if (!projectId) {
        this.logger.warn(
          'Firebase project ID not configured; push provider will operate in dry-run mode',
        );
        return;
      }

      // Avoid re-initializing if already done (e.g. in tests)
      if (!admin.apps.length) {
        const serviceAccountPath = this.config.get<string>(
          'FIREBASE_SERVICE_ACCOUNT_PATH',
        );
        const clientEmail = this.config.get<string>('FCM_CLIENT_EMAIL');
        const privateKey = this.config.get<string>('FCM_PRIVATE_KEY');

        if (serviceAccountPath) {
          // Option 1: Use service account JSON file
          // eslint-disable-next-line @typescript-eslint/no-var-requires
          const serviceAccount = require(serviceAccountPath);
          admin.initializeApp({
            credential: admin.credential.cert(serviceAccount),
          });
        } else if (clientEmail && privateKey) {
          // Option 2: Use individual env vars (for Railway/cloud deploys)
          admin.initializeApp({
            credential: admin.credential.cert({
              projectId,
              clientEmail,
              privateKey: privateKey.replace(/\\n/g, '\n'),
            }),
          });
        } else {
          // Fall back to application default credentials
          admin.initializeApp({
            credential: admin.credential.applicationDefault(),
            projectId,
          });
        }
      }

      this.messaging = admin.messaging();
    } catch (error) {
      this.logger.warn(
        `Firebase initialization failed: ${error.message}. Push provider in dry-run mode.`,
      );
    }
  }

  async send(
    recipient: NotificationRecipient,
    payload: NotificationPayload,
  ): Promise<SendResult> {
    if (!recipient.pushToken) {
      return { success: false, error: 'Recipient has no push token' };
    }

    const message = {
      token: recipient.pushToken,
      notification: {
        title: 'SafeCircle Security Alert',
        body: `Security alert. A possible emergency situation has been triggered for ${payload.userName}. Immediate verification recommended.`,
      },
      data: {
        incidentId: payload.incidentId,
        type: 'emergency_alert',
        accessUrl: payload.accessUrl || '',
        latitude: payload.latitude?.toString() || '',
        longitude: payload.longitude?.toString() || '',
      },
      android: {
        priority: 'high' as const,
        notification: {
          channelId: 'emergency_alerts',
          priority: 'max' as const,
          sound: 'emergency_alert',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'emergency_alert.caf',
            'interruption-level': 'critical',
            badge: 1,
          },
        },
        headers: {
          'apns-priority': '10',
        },
      },
    };

    if (!this.messaging) {
      this.logger.debug(
        `[DRY-RUN] Push to token ${recipient.pushToken.substring(0, 12)}...`,
      );
      return { success: true, externalId: `dry-run-${Date.now()}` };
    }

    try {
      const messageId = await this.messaging.send(message);
      this.logger.log(
        `Push notification sent | messageId: ${messageId}`,
      );
      return { success: true, externalId: messageId };
    } catch (error) {
      this.logger.error(
        `Push delivery failed: ${error.message}`,
        error.stack,
      );

      // Handle invalid/expired tokens
      if (
        error.code === 'messaging/registration-token-not-registered' ||
        error.code === 'messaging/invalid-registration-token'
      ) {
        return {
          success: false,
          error: `Invalid push token: ${error.code}`,
        };
      }

      return { success: false, error: error.message };
    }
  }

  async getStatus(externalId: string): Promise<DeliveryStatus> {
    // FCM does not provide per-message status queries.
    // Delivery receipts are handled via FCM Data API or BigQuery export.
    // For now, if send succeeded we assume delivered.
    return {
      externalId,
      status: externalId.startsWith('dry-run-') ? 'delivered' : 'delivered',
    };
  }
}
