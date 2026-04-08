import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { NotificationsService } from '@/modules/notifications/notifications.service';

/**
 * Processes alert wave dispatch jobs from the 'alert-dispatch' queue.
 *
 * Jobs are enqueued by NotificationsService.dispatchAlertWaves() with
 * progressive delays (wave 1 = immediate, wave 2 = 1 min, wave 3 = 2 min).
 *
 * Each job calls NotificationsService.executeWave() which handles:
 * - Filtering contacts by priority
 * - Sending via SMS, push, voice per channel eligibility
 * - Creating delivery records and timeline events
 * - Retry logic for failed deliveries
 */
@Processor('alert-dispatch', {
  concurrency: 5,
})
export class AlertDispatchProcessor extends WorkerHost {
  private readonly logger = new Logger(AlertDispatchProcessor.name);

  constructor(
    private readonly notificationsService: NotificationsService,
  ) {
    super();
  }

  async process(job: Job): Promise<void> {
    const { incidentId, wave } = job.data;

    this.logger.log(
      `Processing alert dispatch job: wave ${wave} for incident ${incidentId}`,
    );

    try {
      await this.notificationsService.executeWave(job.data);

      this.logger.log(
        `Alert dispatch complete: wave ${wave} for incident ${incidentId}`,
      );
    } catch (error) {
      this.logger.error(
        `Alert dispatch failed: wave ${wave} for incident ${incidentId}: ${error.message}`,
        error.stack,
      );
      throw error; // Let BullMQ handle retry
    }
  }
}
