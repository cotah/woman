import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { JourneyService } from '@/modules/journey/journey.service';

export interface JourneyExpiryJobData {
  journeyId: string;
}

@Processor('journey-expiry', {
  concurrency: 3,
})
export class JourneyExpiryProcessor extends WorkerHost {
  private readonly logger = new Logger(JourneyExpiryProcessor.name);

  constructor(private readonly journeyService: JourneyService) {
    super();
  }

  async process(job: Job<JourneyExpiryJobData>): Promise<void> {
    const { journeyId } = job.data;

    try {
      if (job.name === 'smart-checkin') {
        this.logger.log(`Processing smart check-in for journey ${journeyId}`);
        await this.journeyService.smartCheckin(journeyId);
      } else {
        this.logger.log(`Processing expiry for journey ${journeyId}`);
        await this.journeyService.expire(journeyId);
      }
    } catch (error) {
      this.logger.error(
        `Failed to process ${job.name} for journey ${journeyId}: ${error.message}`,
        error.stack,
      );
      throw error;
    }
  }
}
