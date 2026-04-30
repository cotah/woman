import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, In } from 'typeorm';
import { InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';
import { ConfigService } from '@nestjs/config';
import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import * as Sentry from '@sentry/nestjs';
import { IncidentAudioAsset, TranscriptionStatus } from './entities/incident-audio-asset.entity';
import { IncidentTranscript } from './entities/incident-transcript.entity';
import { DeepgramProvider } from './providers/deepgram.provider';
import { AiClassifierProvider } from './providers/ai-classifier.provider';
import { IncidentsService } from '../incidents/incidents.service';
import { IncidentGateway } from '../../websocket/incident.gateway';

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
    // Pipeline-fix Fix 4 — emit real-time WebSocket events when a
    // transcription completes (migrated from the worker, which
    // previously held this responsibility).
    private readonly incidentGateway: IncidentGateway,
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
    // Pipeline-fix Fix 4 — userId is now part of the payload so
    // processTranscription can re-validate ownership and tag
    // Sentry events with the offending user when cost caps fire.
    await this.audioQueue.add(
      'transcribe',
      {
        audioAssetId: saved.id,
        incidentId,
        userId,
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
  // Transcription pipeline (called by AudioProcessor queue worker)
  // ------------------------------------------------------------------

  /**
   * Process a transcription job. Called by AudioProcessor worker
   * after a chunk is uploaded and enqueued.
   *
   * Pipeline:
   * 1. Validate ownership of the incident
   * 2. Check cost caps (per-incident and per-day)
   * 3. Mark asset as PROCESSING
   * 4. Download audio from S3/R2
   * 5. Transcribe via Deepgram
   * 6. Classify distress signals via OpenAI
   * 7. Persist transcript with AI summary and risk indicators
   * 8. Mark asset as COMPLETED
   * 9. Create timeline events and broadcast real-time updates
   *
   * Errors throw and are retried by BullMQ (up to 3 attempts).
   * Cost cap exhaustion does NOT throw (no retry — would just
   * waste BullMQ attempts hitting the same wall).
   */
  async processTranscription(payload: {
    audioAssetId: string;
    incidentId: string;
    userId?: string;
    storageKey: string;
    mimeType: string;
  }): Promise<void> {
    const { audioAssetId, incidentId, storageKey, mimeType } = payload;
    let userId = payload.userId;

    // Backwards compatibility: legacy job payloads enqueued before
    // pipeline-fix Fix 4 (commit 1e899bd, 2026-04-28) didn't include
    // userId. Recover it from the incident record in those cases.
    //
    // Skipping assertOwnership for legacy payloads is safe because
    // the original uploadChunk call enforced ownership at enqueue
    // time. The fallback just recovers what the payload lost.
    //
    // For NEW payloads, assertOwnership runs as defense-in-depth
    // against forged/replayed Redis jobs.
    if (!userId) {
      userId = await this.incidentsService.getOwnerUserId(incidentId);
      this.logger.warn(
        `[legacy-payload] Job for asset ${audioAssetId} arrived ` +
          `without userId. Recovered userId=${userId} from incident.userId. ` +
          `This indicates a stale job enqueued before pipeline-fix ` +
          `(commit 1e899bd, 2026-04-28).`,
      );
    } else {
      // 1. Validate ownership — defense in depth: even though the
      // job was enqueued by an authenticated upload, the worker
      // re-validates in case of replayed/forged payloads.
      await this.incidentsService.assertOwnership(incidentId, userId);
    }

    // Idempotency pre-check: if a transcript already exists for this
    // asset, this is a BullMQ retry of a job that previously succeeded
    // past the save step but threw on a later side effect. Skip
    // reprocessing to avoid (a) re-paying Deepgram + AI Classifier
    // costs, (b) duplicate incident_events / risk signals / broadcasts.
    //
    // Placed BEFORE cost caps + status mutation so that:
    //  - retry preserves the terminal status from the prior attempt
    //    (FAILED or COMPLETED — no regression to PROCESSING)
    //  - cheapest check (1 SELECT EXISTS) runs before paid checks
    //
    // Migration 004 added a UNIQUE constraint on audio_asset_id as
    // the final defense; the catch around save() below covers the
    // (theoretical) race the pre-check might miss.
    if (await this.transcriptRepo.exists({ where: { audioAssetId } })) {
      this.logger.warn(
        `Transcript already exists for asset ${audioAssetId} — ` +
          `BullMQ retry detected after partial completion on a previous ` +
          `attempt. Skipping reprocessing (no double-charge, no duplicate ` +
          `side effects).`,
      );
      return;
    }

    this.logger.log(`Processing transcription for asset ${audioAssetId}`);

    // 2a. Cost cap — per-incident
    // Counts assets that have already passed Deepgram (each one
    // = one paid call). PENDING assets are excluded because they
    // have not cost anything yet — they will be counted when
    // their own job runs.
    const maxPerIncident = this.config.get<number>(
      'MAX_TRANSCRIPTIONS_PER_INCIDENT',
      20,
    );
    const processedCount = await this.audioAssetRepo.count({
      where: {
        incidentId,
        transcriptionStatus: In([
          TranscriptionStatus.PROCESSING,
          TranscriptionStatus.COMPLETED,
          TranscriptionStatus.FAILED,
        ]),
      },
    });
    if (processedCount >= maxPerIncident) {
      await this.markCostCapHit({
        audioAssetId,
        incidentId,
        userId,
        reason: 'per_incident',
        count: processedCount,
        limit: maxPerIncident,
      });
      return;
    }

    // 2b. Cost cap — per-day (global across all users/incidents)
    // Sums duration_seconds of assets in the last 24h that have
    // gone through Deepgram (processing/completed/failed all
    // counted — failed because abusers could otherwise force
    // failures to dodge the cap).
    const maxPerDayMinutes = this.config.get<number>(
      'MAX_AUDIO_MINUTES_PER_DAY',
      2000,
    );
    const dayResult = await this.audioAssetRepo
      .createQueryBuilder('asset')
      .select('COALESCE(SUM(asset.duration_seconds), 0) / 60.0', 'minutes')
      .where("asset.created_at > NOW() - INTERVAL '24 hours'")
      .andWhere('asset.transcription_status IN (:...statuses)', {
        statuses: ['processing', 'completed', 'failed'],
      })
      .getRawOne<{ minutes: string }>();
    const minutesUsed = parseFloat(dayResult?.minutes ?? '0');
    if (minutesUsed >= maxPerDayMinutes) {
      await this.markCostCapHit({
        audioAssetId,
        incidentId,
        userId,
        reason: 'per_day',
        count: minutesUsed,
        limit: maxPerDayMinutes,
      });
      return;
    }

    // 3. Mark as processing (only after caps clear, so a capped
    // asset never transitions to PROCESSING and then back to
    // FAILED — avoids confusing audit trail).
    await this.audioAssetRepo.update(audioAssetId, {
      transcriptionStatus: TranscriptionStatus.PROCESSING,
    });

    try {
      // 4. Download from S3
      const audioBuffer = await this.downloadFromS3(storageKey);

      // 5. Transcribe
      const transcriptionResult = await this.deepgramProvider.transcribe(
        audioBuffer,
        { mimeType },
      );

      if (
        !transcriptionResult.text ||
        transcriptionResult.text.trim().length === 0
      ) {
        this.logger.log(`No speech detected in asset ${audioAssetId}`);
        await this.audioAssetRepo.update(audioAssetId, {
          transcriptionStatus: TranscriptionStatus.COMPLETED,
        });
        return;
      }

      // 6. Classify for distress
      const classification = await this.aiClassifier.classifyDistress(
        transcriptionResult.text,
        { incidentId },
      );

      // 7. Save transcript
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

      try {
        await this.transcriptRepo.save(transcript);
      } catch (error) {
        // Defense in depth: if the pre-check above missed (which
        // shouldn't happen with single-worker BullMQ semantics — same
        // job, same worker), the UNIQUE constraint from migration 004
        // catches the duplicate at the DB layer. PostgreSQL error
        // code 23505 = unique_violation.
        if (error?.code === '23505') {
          this.logger.warn(
            `UniqueViolation on transcript save for asset ${audioAssetId} ` +
              `— duplicate detected at DB layer. Skipping side effects.`,
          );
          return;
        }
        throw error; // Other errors: bubble up for BullMQ retry
      }

      // 8. Mark as completed
      await this.audioAssetRepo.update(audioAssetId, {
        transcriptionStatus: TranscriptionStatus.COMPLETED,
      });

      // 9a. Persistent timeline event (DB)
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

      // 9c. Emit risk signals to the engine (Bug 8.a fix).
      // AiClassifier already shaped the result. Translate to engine
      // vocabulary using the two complementary rules from
      // risk-rules.config.ts:
      //   - audio_distress_detected (+25): any distress at all
      //   - help_phrase_detected (+35): explicit help request
      // Both are oncePerIncident=false, liveOnly=true — multiple
      // chunks accumulate score; test-mode incidents see no effect.
      //
      // Wrapped in try/catch with logger.error: if processRiskSignal
      // throws (commonly because the incident transitioned to
      // terminal status while the chunk was being processed), we
      // still complete the transcription. The signal would have
      // been informational on a non-active incident anyway.
      if (classification.isDistress || classification.signals.length > 0) {
        try {
          await this.incidentsService.processRiskSignal(incidentId, userId, {
            type: 'audio_distress_detected',
            payload: {
              audioAssetId,
              transcriptId: transcript.id,
              riskLevel: classification.riskLevel,
              confidence: classification.confidence,
              signalCount: classification.signals.length,
            },
          });

          const hasHelpRequest = classification.signals.some(
            (s) => s.type === 'help_request',
          );
          if (hasHelpRequest) {
            await this.incidentsService.processRiskSignal(
              incidentId,
              userId,
              {
                type: 'help_phrase_detected',
                payload: {
                  audioAssetId,
                  transcriptId: transcript.id,
                  excerpts: classification.signals
                    .filter((s) => s.type === 'help_request')
                    .map((s) => s.excerpt)
                    .filter(Boolean),
                },
              },
            );
          }
        } catch (error) {
          this.logger.error(
            `Failed to emit risk signal for asset ${audioAssetId} ` +
              `(incident ${incidentId}): ${error.message}. ` +
              `Common cause: incident transitioned to terminal status ` +
              `during transcription. Transcript was saved successfully; ` +
              `pipeline will complete normally.`,
            error.stack,
          );
        }
      }

      // 9b. Real-time broadcast (migrated from AudioProcessor in Fix 4).
      // Mobile clients subscribed to incident:${id} room get notified
      // immediately, without polling the timeline endpoint.
      this.incidentGateway.broadcastTimelineEvent(incidentId, {
        type: 'transcription_completed',
        payload: {
          audioAssetId,
          transcriptId: transcript.id,
          confidence: transcriptionResult.confidence,
          hasDistressSignals: classification.signals.length > 0,
        },
        timestamp: new Date().toISOString(),
      });

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

  /**
   * Cost-cap-hit handling: mark the asset as FAILED, record an
   * incident_events row with the reason, and capture a Sentry
   * warning. Returns without throwing — BullMQ should NOT retry,
   * because the cap will keep firing.
   */
  private async markCostCapHit(args: {
    audioAssetId: string;
    incidentId: string;
    userId: string;
    reason: 'per_incident' | 'per_day';
    count: number;
    limit: number;
  }): Promise<void> {
    const { audioAssetId, incidentId, userId, reason, count, limit } = args;

    await this.audioAssetRepo.update(audioAssetId, {
      transcriptionStatus: TranscriptionStatus.FAILED,
    });

    await this.createIncidentEvent(incidentId, 'ai_analysis_result', {
      source: 'cost_cap',
      reason,
      count,
      limit,
    });

    Sentry.captureMessage('cost_cap_hit', {
      level: 'warning',
      tags: { reason, incidentId, userId, audioAssetId },
    });

    this.logger.warn(
      `Cost cap hit for asset ${audioAssetId} (${reason}: ${count}/${limit}) — ` +
        `transcription skipped, no retry`,
    );
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
    payload: Record<string, unknown>,
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
