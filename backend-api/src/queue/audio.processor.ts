import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { Job } from 'bullmq';
import { AudioService } from '@/modules/audio/audio.service';

export interface AudioTranscriptionJobData {
  audioAssetId: string;
  incidentId: string;
  userId: string;
  storageKey: string;
  mimeType: string;
}

/**
 * Thin BullMQ worker that delegates the actual transcription
 * pipeline to AudioService.processTranscription. Keeping this
 * processor as a small orchestration layer means the domain
 * logic (S3 download, Deepgram, AI classifier, persistence,
 * timeline events, real-time broadcast) lives in a single
 * place — the service — instead of being split between the
 * service and the worker.
 */
@Processor('audio-processing', {
  concurrency: 3, // limit concurrent transcription jobs (CPU/API intensive)
})
export class AudioProcessor extends WorkerHost {
  private readonly logger = new Logger(AudioProcessor.name);

  constructor(private readonly audioService: AudioService) {
    super();
  }

  async process(job: Job<AudioTranscriptionJobData>): Promise<void> {
    this.logger.log(
      `Processing job ${job.id} for asset ${job.data.audioAssetId} ` +
        `(incident ${job.data.incidentId})`,
    );
    await this.audioService.processTranscription(job.data);
  }
}
