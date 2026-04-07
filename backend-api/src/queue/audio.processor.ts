import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Job } from 'bullmq';
import { ConfigService } from '@nestjs/config';
import { S3Client, GetObjectCommand } from '@aws-sdk/client-s3';
import { IncidentAudioAsset } from '@/modules/audio/entities/incident-audio-asset.entity';
import { IncidentTranscript } from '@/modules/audio/entities/incident-transcript.entity';
import { IncidentGateway } from '@/websocket/incident.gateway';

export interface AudioTranscriptionJobData {
  audioAssetId: string;
  incidentId: string;
  storageKey: string;
  language?: string;
}

@Processor('audio', {
  concurrency: 3, // limit concurrent transcription jobs (CPU/API intensive)
})
export class AudioProcessor extends WorkerHost {
  private readonly logger = new Logger(AudioProcessor.name);
  private readonly s3Client: S3Client;
  private readonly bucket: string;

  constructor(
    @InjectRepository(IncidentAudioAsset)
    private readonly audioAssetRepo: Repository<IncidentAudioAsset>,
    @InjectRepository(IncidentTranscript)
    private readonly transcriptRepo: Repository<IncidentTranscript>,
    private readonly configService: ConfigService,
    private readonly incidentGateway: IncidentGateway,
  ) {
    super();
    const region = this.configService.get<string>('AWS_REGION') || 'us-east-1';
    this.s3Client = new S3Client({ region });
    this.bucket = this.configService.get<string>('S3_BUCKET') || '';
  }

  async process(job: Job<AudioTranscriptionJobData>): Promise<void> {
    const { audioAssetId, incidentId, storageKey, language } = job.data;
    this.logger.log(
      `Processing audio transcription for asset ${audioAssetId} (incident ${incidentId})`,
    );

    // Mark as processing
    await this.audioAssetRepo.update(audioAssetId, {
      transcriptionStatus: 'processing' as any,
    });

    try {
      // Step 1: Download audio from S3
      const audioBuffer = await this.downloadFromS3(storageKey);
      await job.updateProgress(20);

      // Step 2: Send to transcription service
      const transcriptionResult = await this.transcribe(
        audioBuffer,
        language || 'en',
      );
      await job.updateProgress(70);

      // Step 3: Analyze for distress signals
      const distressAnalysis = await this.analyzeDistressSignals(
        transcriptionResult.text,
      );
      await job.updateProgress(90);

      // Step 4: Save transcript
      const transcript = this.transcriptRepo.create({
        audioAssetId,
        incidentId,
        text: transcriptionResult.text,
        confidence: transcriptionResult.confidence,
        language: language || 'en',
        distressSignals: distressAnalysis.signals,
        aiSummary: distressAnalysis.summary,
        aiRiskIndicators: distressAnalysis.riskIndicators,
      });
      await this.transcriptRepo.save(transcript);

      // Step 5: Mark asset as completed
      await this.audioAssetRepo.update(audioAssetId, {
        transcriptionStatus: 'completed' as any,
      });

      // Step 6: Broadcast timeline event
      this.incidentGateway.broadcastTimelineEvent(incidentId, {
        type: 'transcription_completed',
        payload: {
          audioAssetId,
          transcriptId: transcript.id,
          confidence: transcriptionResult.confidence,
          hasDistressSignals: distressAnalysis.signals.length > 0,
        },
        timestamp: new Date().toISOString(),
      });

      await job.updateProgress(100);
      this.logger.log(
        `Transcription completed for asset ${audioAssetId}`,
      );
    } catch (error) {
      await this.audioAssetRepo.update(audioAssetId, {
        transcriptionStatus: 'failed' as any,
      });

      this.logger.error(
        `Transcription failed for asset ${audioAssetId}: ${error.message}`,
        error.stack,
      );
      throw error; // re-throw for BullMQ retry
    }
  }

  private async downloadFromS3(storageKey: string): Promise<Buffer> {
    const command = new GetObjectCommand({
      Bucket: this.bucket,
      Key: storageKey,
    });
    const response = await this.s3Client.send(command);
    const chunks: Uint8Array[] = [];
    for await (const chunk of response.Body as AsyncIterable<Uint8Array>) {
      chunks.push(chunk);
    }
    return Buffer.concat(chunks);
  }

  /**
   * Transcription integration point.
   * Replace with actual STT provider (Whisper API, Google Speech-to-Text, etc.)
   */
  private async transcribe(
    _audioBuffer: Buffer,
    _language: string,
  ): Promise<{ text: string; confidence: number }> {
    // TODO: integrate real STT provider
    // Example: const result = await this.whisperClient.transcribe(audioBuffer, { language });
    this.logger.warn(
      'Using placeholder transcription -- integrate real STT provider',
    );
    return {
      text: '[Transcription placeholder - integrate STT provider]',
      confidence: 0,
    };
  }

  /**
   * Distress signal analysis integration point.
   * Replace with actual NLP / AI analysis service.
   */
  private async analyzeDistressSignals(
    _text: string,
  ): Promise<{
    signals: Array<{ keyword: string; severity: string }>;
    summary: string | null;
    riskIndicators: Array<{ indicator: string; confidence: number }>;
  }> {
    // TODO: integrate real distress detection
    return {
      signals: [],
      summary: null,
      riskIndicators: [],
    };
  }
}
