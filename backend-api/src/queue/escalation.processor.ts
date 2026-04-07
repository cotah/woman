import { Processor, WorkerHost, InjectQueue } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Job, Queue } from 'bullmq';
import {
  Incident,
  IncidentStatus,
} from '@/modules/incidents/entities/incident.entity';
import { IncidentEvent } from '@/modules/incidents/entities/incident-event.entity';
import { AlertDelivery } from '@/modules/notifications/entities/alert-delivery.entity';
import { IncidentGateway } from '@/websocket/incident.gateway';

export interface EscalationJobData {
  incidentId: string;
  wave: number;
  contactIds: string[];
  channels: Array<'push' | 'sms' | 'voice_call' | 'email'>;
  messageBody: string;
  /** Delay in ms before the next escalation wave fires */
  nextWaveDelayMs?: number;
  /** Max escalation wave before stopping */
  maxWaves?: number;
}

/**
 * Escalation processor manages multi-wave alert dispatch.
 *
 * Wave 1: Push + SMS to priority-1 contacts
 * Wave 2: Push + SMS + Voice to priority-1 + priority-2 contacts
 * Wave 3: All channels to all contacts
 *
 * Each wave is a separate delayed job so the system can cancel
 * future waves if the incident is resolved.
 */
@Processor('escalation', {
  concurrency: 5,
})
export class EscalationProcessor extends WorkerHost {
  private readonly logger = new Logger(EscalationProcessor.name);

  constructor(
    @InjectRepository(Incident)
    private readonly incidentRepo: Repository<Incident>,
    @InjectRepository(IncidentEvent)
    private readonly eventRepo: Repository<IncidentEvent>,
    @InjectRepository(AlertDelivery)
    private readonly alertRepo: Repository<AlertDelivery>,
    @InjectQueue('alerts')
    private readonly alertQueue: Queue,
    @InjectQueue('escalation')
    private readonly escalationQueue: Queue,
    private readonly incidentGateway: IncidentGateway,
  ) {
    super();
  }

  async process(job: Job<EscalationJobData>): Promise<void> {
    const {
      incidentId,
      wave,
      contactIds,
      channels,
      messageBody,
      nextWaveDelayMs,
      maxWaves,
    } = job.data;

    this.logger.log(
      `Processing escalation wave ${wave} for incident ${incidentId}`,
    );

    // Check if incident is still active (might have been resolved/cancelled)
    const incident = await this.incidentRepo.findOne({
      where: { id: incidentId },
    });

    if (!incident) {
      this.logger.warn(`Incident ${incidentId} not found, skipping wave ${wave}`);
      return;
    }

    const activeStatuses: IncidentStatus[] = [
      IncidentStatus.ACTIVE,
      IncidentStatus.ESCALATED,
    ];

    if (!activeStatuses.includes(incident.status)) {
      this.logger.log(
        `Incident ${incidentId} is ${incident.status}, skipping escalation wave ${wave}`,
      );
      return;
    }

    // Update incident escalation wave
    await this.incidentRepo.update(incidentId, {
      escalationWave: wave,
      status: IncidentStatus.ESCALATED,
    });

    // Create alert delivery records and enqueue alert jobs
    const alertJobs: { name: string; data: any; opts?: any }[] = [];

    for (const contactId of contactIds) {
      for (const channel of channels) {
        const delivery = this.alertRepo.create({
          incidentId,
          contactId,
          channel: channel as any,
          status: 'queued' as any,
          wave,
          messageBody,
        });
        const saved = await this.alertRepo.save(delivery);

        alertJobs.push({
          name: `alert-${saved.id}`,
          data: {
            alertDeliveryId: saved.id,
            incidentId,
            contactId,
            channel,
            messageBody,
          },
          opts: {
            attempts: 3,
            backoff: {
              type: 'exponential',
              delay: 5000,
            },
          },
        });
      }
    }

    // Bulk enqueue alert jobs
    if (alertJobs.length > 0) {
      await this.alertQueue.addBulk(alertJobs);
      this.logger.log(
        `Enqueued ${alertJobs.length} alerts for wave ${wave} of incident ${incidentId}`,
      );
    }

    // Log escalation timeline event
    const event = this.eventRepo.create({
      incidentId,
      type: 'escalation_wave' as any,
      payload: {
        wave,
        contactCount: contactIds.length,
        channels,
        alertCount: alertJobs.length,
      },
      source: 'escalation_processor',
    });
    await this.eventRepo.save(event);

    // Broadcast real-time update
    this.incidentGateway.broadcastIncidentUpdate(incidentId, {
      status: 'escalated',
      escalationWave: wave,
      alertsEnqueued: alertJobs.length,
    });

    this.incidentGateway.broadcastTimelineEvent(incidentId, {
      type: 'escalation_wave',
      payload: { wave, alertCount: alertJobs.length },
      timestamp: new Date().toISOString(),
    });

    // Schedule next wave if applicable
    const effectiveMaxWaves = maxWaves ?? 3;
    const effectiveDelay = nextWaveDelayMs ?? 120_000; // default 2 minutes

    if (wave < effectiveMaxWaves) {
      this.logger.log(
        `Scheduling escalation wave ${wave + 1} for incident ${incidentId} in ${effectiveDelay}ms`,
      );

      await this.escalationQueue.add(
        `escalation-wave-${wave + 1}`,
        {
          ...job.data,
          wave: wave + 1,
        },
        {
          delay: effectiveDelay,
          jobId: `escalation-${incidentId}-wave-${wave + 1}`,
          removeOnComplete: true,
        },
      );
    } else {
      this.logger.log(
        `Max escalation waves (${effectiveMaxWaves}) reached for incident ${incidentId}`,
      );
    }
  }
}
