import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';
import { ConfigService } from '@nestjs/config';
import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { IncidentAudioAsset, TranscriptionStatus } from './entities/incident-audio-asset.entity';
import { IncidentTranscript } from './entities/incident-transcript.entity';
import { DeepgramProvider } from './providers/deepgram.provider';
import { AiClassifierProvider } from './providers/ai-classifier.provider';
import { IncidentsService } from '../incidents/incidents.service';

@Injectable()
export class AudioService {
  private readonly logger = new Logger(AudioService.name);
  private readonly s3: S3Client;
  private readonly bucketName: string;

  constructor(
    @InjectRepository(IncidentAudioAsset)
    private readonly audioAssetRepo: Repository<IncidentAudioAsset>,
    @InjectRepository(IncidentTranscript)
    private readonly transcriptRepo: Repository<IncidentTranscript>,
    @InjectQueue('audio-processing')
    private readonly audioQueue: Queue,
    private readonly config: ConfigService,
    private readonly deepgramProvider: DeepgramProvider,
    private readonly aiClassifier: AiClassifierProvider,
    // IDOR fix B2 — needed to call assertOwnership before any operation
    private readonly incidentsService: IncidentsService,
  ) {
    this.bucketName = this.config.get<string>('S3_AUDIO_BUCKET', 'safecircle-audio');

    this.s3 = new S3Client({
      region: this.config.get<string>('AWS_REGION', 'us-east-1'),
      credentials: {
        accessKeyId: this.config.get<string>('AWS_ACCESS_KEY_ID', ''),
        secretAccessKey: this.config.get<string>('AWS_SECRET_ACCESS_KEY', ''),
      },
      ...(this.config.get<string>('S3_ENDPOINT')
        ? {
            endpoint: this.config.get<string>('S3_ENDPOINT'),
            forcePathStyle: true,
          }
        : {}),
    });
  }

  // ------------------------------------------------------------------
  // Upload
  // ------------------------------------------------------------------

  /**
   * Upload an audio chunk for an incident.
   * Stores the file in S3, creates a metadata record, and queues transcription.
   */
  async uploadChunk(
    incidentId: string,
    userId: string,
    file: Express.Multer.File,
    durationSeconds: number,
  ): Promise<IncidentAudioAsset> {
    // IDOR fix B2 — validate ownership before any operation
    await this.incidentsService.assertOwnership(incidentId, userId);

    // Determine chunk index (next in sequence)
    const lastChunk = await this.audioAssetRepo.findOne({
      where: { incidentId },
      order: { chunkIndex: 'DESC' },
    });
    const chunkIndex = lastChunk ? lastChunk.chunkIndex + 1 : 0;

    // Build S3 key
    const storageKey = this.buildStorageKey(incidentId, chunkIndex, file.mimetype);

    // Upload to S3
    await this.uploadToS3(storageKey, file.buffer, file.mimetype);

    // Create DB record
    const asset = this.audioAssetRepo.create({
      incidentId,
      chunkIndex,
      durationSeconds,
      storageKey,
      mimeType: file.mimetype || 'audio/webm',
      sizeBytes: file.size,
      transcriptionStatus: TranscriptionStatus.PENDING,
    });

    const saved = await this.audioAssetRepo.save(asset);

    // Create incident event
    await this.createIncidentEvent(incidentId, 'audio_chunk_uploaded', {
      audioAssetId: saved.id,
      chunkIndex,
      durationSeconds,
      sizeBytes: file.size,
    });

    // Queue transcription job
    await this.audioQueue.add(
      'transcribe',
      {
        audioAssetId: saved.id,
        incidentId,
        storageKey,
        mimeType: file.mimetype,
      },
      {
        attempts: 3,
        backoff: { type: 'exponential', delay: 5000 },
        removeOnComplete: true,
      },
    );

    this.logger.log(
      `Audio chunk ${chunkIndex} uploaded for incident ${incidentId} | ` +
        `size=${file.size} key=${storageKey}`,
    );

    return saved;
  }

  // ------------------------------------------------------------------
  // Query
  // ------------------------------------------------------------------

  /**
   * List all audio chunks for an incident.
   */
  async listChunks(incidentId: string, userId: string): Promise<IncidentAudioAsset[]> {
    // IDOR fix B2 — validate ownership before any operation
    await this.incidentsService.assertOwnership(incidentId, userId);

    return this.audioAssetRepo.find({
      where: { incidentId },
      order: { chunkIndex: 'ASC' },
    });
  }

  /**
   * Get a pre-signed URL for downloading an audio chunk.
   */
  async getDownloadUrl(
    incidentId: string,
    userId: string,
    assetId: string,
  ): Promise<string> {
    // IDOR fix B2 — validate ownership before any operation
    await this.incidentsService.assertOwnership(incidentId, userId);

    const asset = await this.audioAssetRepo.findOne({ where: { id: assetId } });

    // IDOR cross-check B2 — verify asset belongs to the asserted incident,
    // not just any incident the user owns. Without this, an attacker who
    // owns incident X could request /incidents/X/audio/{Y}/download where
    // Y is an asset id of someone else's incident; assertOwnership(X, user)
    // passes, the asset loads, and a presigned URL is emitted. Same
    // NotFoundException + same message as "asset truly does not exist"
    // so neither status nor body discloses cross-incident existence.
    if (!asset || asset.incidentId !== incidentId) {
      throw new NotFoundException(`Audio asset ${assetId} not found`);
    }

    const command = new GetObjectCommand({
      Bucket: this.bucketName,
      Key: asset.storageKey,
    });

    return getSignedUrl(this.s3, command, { expiresIn: 3600 });
  }

  /**
   * Get transcripts for an incident.
   */
  async getTranscripts(
    incidentId: string,
    userId: string,
  ): Promise<IncidentTranscript[]> {
    // IDOR fix B2 — validate ownership before any operation
    await this.incidentsService.assertOwnership(incidentId, userId);

    return this.transcriptRepo.find({
      where: { incidentId },
      order: { createdAt: 'ASC' },
    });
  }

  // ------------------------------------------------------------------
  // Transcription pipeline (called by queue processor)
  // ------------------------------------------------------------------

  /**
   * Process a transcription job. Called by the BullMQ worker.
   *
   * @deprecated NO CALLERS — investigation pending.
   * This method has no callers in src/. The audio queue worker
   * (audio.processor.ts) does its own transcription against a
   * different entity (IncidentAudioAsset, not AudioAsset).
   *
   * TODO(B2-followup): determine if this is dead code or a
   * latent wiring bug. If dead code, remove. If bug, route the
   * processor to call this service.
   *
   * Not in scope of B2 (no public endpoint exposes this method).
   */
  async processTranscription(payload: {
    audioAssetId: string;
    incidentId: string;
    storageKey: string;
    mimeType: string;
  }): Promise<void> {
    const { audioAssetId, incidentId, storageKey, mimeType } = payload;

    this.logger.log(`Processing transcription for asset ${audioAssetId}`);

    // Update status to processing
    await this.audioAssetRepo.update(audioAssetId, {
      transcriptionStatus: TranscriptionStatus.PROCESSING,
    });

    try {
      // Download from S3
      const audioBuffer = await this.downloadFromS3(storageKey);

      // Transcribe
      const transcriptionResult = await this.deepgramProvider.transcribe(
        audioBuffer,
        { mimeType },
      );

      if (!transcriptionResult.text || transcriptionResult.text.trim().length === 0) {
        this.logger.log(`No speech detected in asset ${audioAssetId}`);
        await this.audioAssetRepo.update(audioAssetId, {
          transcriptionStatus: TranscriptionStatus.COMPLETED,
        });
        return;
      }

      // Classify for distress
      const classification = await this.aiClassifier.classifyDistress(
        transcriptionResult.text,
        { incidentId },
      );

      // Save transcript
      const transcript = this.transcriptRepo.create({
        audioAssetId,
        incidentId,
        text: transcriptionResult.text,
        confidence: transcriptionResult.confidence,
        language: transcriptionResult.language,
        distressSignals: classification.signals,
        aiSummary: classification.summary,
        aiRiskIndicators: classification.signals.map((s) => ({
          type: s.type,
          confidence: s.confidence,
          description: s.description,
        })),
      });

      await this.transcriptRepo.save(transcript);

      // Update asset status
      await this.audioAssetRepo.update(audioAssetId, {
        transcriptionStatus: TranscriptionStatus.COMPLETED,
      });

      // Create incident event
      await this.createIncidentEvent(incidentId, 'transcription_completed', {
        audioAssetId,
        transcriptId: transcript.id,
        textLength: transcriptionResult.text.length,
        confidence: transcriptionResult.confidence,
        isDistress: classification.isDistress,
        riskLevel: classification.riskLevel,
        signalCount: classification.signals.length,
      });

      // If distress detected, queue an AI analysis result event
      if (classification.isDistress) {
        await this.createIncidentEvent(incidentId, 'ai_analysis_result', {
          source: 'audio_classifier',
          riskLevel: classification.riskLevel,
          confidence: classification.confidence,
          summary: classification.summary,
          signals: classification.signals,
        });
      }

      this.logger.log(
        `Transcription completed for asset ${audioAssetId}: ` +
          `${transcriptionResult.text.length} chars, distress=${classification.isDistress}`,
      );
    } catch (error) {
      this.logger.error(
        `Transcription failed for asset ${audioAssetId}: ${error.message}`,
        error.stack,
      );

      await this.audioAssetRepo.update(audioAssetId, {
        transcriptionStatus: TranscriptionStatus.FAILED,
      });

      await this.createIncidentEvent(incidentId, 'ai_analysis_result', {
        source: 'audio_transcription',
        error: error.message,
        audioAssetId,
      });

      throw error; // Let BullMQ retry
    }
  }

  // ------------------------------------------------------------------
  // S3 helpers
  // ------------------------------------------------------------------

  private buildStorageKey(
    incidentId: string,
    chunkIndex: number,
    mimeType: string,
  ): string {
    const ext = this.mimeToExtension(mimeType);
    return `incidents/${incidentId}/audio/chunk_${String(chunkIndex).padStart(4, '0')}.${ext}`;
  }

  private async uploadToS3(
    key: string,
    buffer: Buffer,
    contentType: string,
  ): Promise<void> {
    const command = new PutObjectCommand({
      Bucket: this.bucketName,
      Key: key,
      Body: buffer,
      ContentType: contentType,
      ServerSideEncryption: 'AES256',
    });

    await this.s3.send(command);
  }

  private async downloadFromS3(key: string): Promise<Buffer> {
    const command = new GetObjectCommand({
      Bucket: this.bucketName,
      Key: key,
    });

    const response = await this.s3.send(command);
    const stream = response.Body as any;

    // Collect stream into buffer
    const chunks: Buffer[] = [];
    for await (const chunk of stream) {
      chunks.push(Buffer.from(chunk));
    }
    return Buffer.concat(chunks);
  }

  private mimeToExtension(mimeType: string): string {
    const map: Record<string, string> = {
      'audio/webm': 'webm',
      'audio/ogg': 'ogg',
      'audio/mp4': 'm4a',
      'audio/mpeg': 'mp3',
      'audio/wav': 'wav',
      'audio/x-wav': 'wav',
      'audio/aac': 'aac',
    };
    return map[mimeType] || 'webm';
  }

  private async createIncidentEvent(
    incidentId: string,
    type: string,
    payload: Record<string, any>,
  ): Promise<void> {
    try {
      await this.audioAssetRepo.manager.query(
        `INSERT INTO incident_events (incident_id, type, payload, source, is_internal)
         VALUES ($1, $2, $3, 'audio_service', false)`,
        [incidentId, type, JSON.stringify(payload)],
      );
    } catch (error) {
      this.logger.error(
        `Failed to create incident event (${type}): ${error.message}`,
      );
    }
  }
}
