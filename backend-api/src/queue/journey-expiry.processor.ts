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

    this.logger.log(`Processing expiry for journey ${journeyId}`);

    try {
      await this.journeyService.expire(journeyId);
    } catch (error) {
      this.logger.error(
        `Failed to process expiry for journey ${journeyId}: ${error.message}`,
        error.stack,
      );
      throw error;
    }
  }
}
