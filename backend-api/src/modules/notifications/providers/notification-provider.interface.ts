export interface NotificationRecipient {
  contactId: string;
  name: string;
  phone?: string;
  email?: string;
  pushToken?: string;
  locale: string;
}

export interface NotificationPayload {
  incidentId: string;
  userName: string;
  message: string;
  accessUrl?: string;
  latitude?: number;
  longitude?: number;
}

export interface SendResult {
  success: boolean;
  externalId?: string;
  error?: string;
}

export interface DeliveryStatus {
  externalId: string;
  status: 'queued' | 'sending' | 'delivered' | 'failed';
  updatedAt?: Date;
  error?: string;
}

export const NOTIFICATION_PROVIDER = Symbol('NOTIFICATION_PROVIDER');

export interface NotificationProvider {
  readonly channel: 'push' | 'sms' | 'voice_call' | 'email';

  /**
   * Send a notification to a single recipient.
   */
  send(
    recipient: NotificationRecipient,
    payload: NotificationPayload,
  ): Promise<SendResult>;

  /**
   * Query the delivery status of a previously sent notification.
   */
  getStatus(externalId: string): Promise<DeliveryStatus>;
}
