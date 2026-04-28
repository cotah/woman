import { NotFoundException } from '@nestjs/common';
import * as Sentry from '@sentry/nestjs';
import { AudioService } from '../../src/modules/audio/audio.service';
import { TranscriptionStatus } from '../../src/modules/audio/entities/incident-audio-asset.entity';

/**
 * Audio pipeline integration test (Fix 6 of pipeline-fix).
 *
 * Covers AudioService.processTranscription — the canonical worker
 * pipeline introduced in Fix 4 (commit 1e899bd). Validates:
 *
 *   1. Happy path — transcribe, classify, persist, broadcast
 *   2. Cost cap per-incident — abort before Deepgram, FAILED, no retry
 *   3. Cost cap per-day — abort before Deepgram, FAILED, no retry
 *   4. Ownership fail — assertOwnership throws, no side effects
 *   5. Deepgram error — PROCESSING → FAILED, rethrow for BullMQ retry
 *
 * Regression net for the 3+1 structural bugs that left this pipeline
 * inert in production. Each scenario fails loudly if any of these
 * regressions sneak back in.
 */

// Stub Sentry SDK so captureMessage is observable in tests without
// touching the real Sentry instance configured via instrument.ts.
jest.mock('@sentry/nestjs', () => ({
  captureMessage: jest.fn(),
  captureException: jest.fn(),
}));

// Stub S3 client so downloadFromS3 returns a deterministic buffer
// each call (a fresh async iterator per send invocation, otherwise
// the second test would consume an already-exhausted generator).
jest.mock('@aws-sdk/client-s3', () => ({
  S3Client: jest.fn().mockImplementation(() => ({
    send: jest.fn().mockImplementation(() =>
      Promise.resolve({
        Body: (async function* () {
          yield Buffer.from('fake-audio-bytes');
        })(),
      }),
    ),
  })),
  PutObjectCommand: jest.fn(),
  GetObjectCommand: jest.fn(),
}));
jest.mock('@aws-sdk/s3-request-presigner', () => ({
  getSignedUrl: jest.fn().mockResolvedValue('https://signed.example/x'),
}));

describe('AudioPipeline (processTranscription)', () => {
  const USER = '11111111-1111-1111-1111-111111111111';
  const INCIDENT = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  const ASSET = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  const STORAGE_KEY = 'incidents/A/audio/chunk_0000.webm';

  const basePayload = {
    audioAssetId: ASSET,
    incidentId: INCIDENT,
    userId: USER,
    storageKey: STORAGE_KEY,
    mimeType: 'audio/webm',
  };

  let audioService: AudioService;

  // Per-test mocks (re-built in beforeEach so jest.fn() call history
  // is isolated per scenario).
  let assertOwnership: jest.Mock;
  let assetCount: jest.Mock;
  let assetUpdate: jest.Mock;
  let dayMinutes: jest.Mock;
  let managerQuery: jest.Mock;
  let transcriptCreate: jest.Mock;
  let transcriptSave: jest.Mock;
  let deepgramTranscribe: jest.Mock;
  let aiClassify: jest.Mock;
  let broadcastTimelineEvent: jest.Mock;

  beforeEach(() => {
    jest.clearAllMocks();

    assertOwnership = jest.fn().mockResolvedValue(undefined);
    assetCount = jest.fn().mockResolvedValue(0);
    assetUpdate = jest.fn().mockResolvedValue(undefined);
    dayMinutes = jest.fn().mockResolvedValue({ minutes: '0' });
    managerQuery = jest.fn().mockResolvedValue(undefined);
    transcriptCreate = jest
      .fn()
      .mockImplementation((data) => ({ id: 'transcript-1', ...data }));
    transcriptSave = jest
      .fn()
      .mockImplementation((d) => Promise.resolve(d));
    deepgramTranscribe = jest.fn();
    aiClassify = jest.fn();
    broadcastTimelineEvent = jest.fn();

    const audioAssetRepo: any = {
      count: assetCount,
      update: assetUpdate,
      findOne: jest.fn().mockResolvedValue(null),
      manager: { query: managerQuery },
      createQueryBuilder: jest.fn(() => ({
        select: jest.fn().mockReturnThis(),
        where: jest.fn().mockReturnThis(),
        andWhere: jest.fn().mockReturnThis(),
        getRawOne: dayMinutes,
      })),
    };
    const transcriptRepo: any = {
      create: transcriptCreate,
      save: transcriptSave,
      find: jest.fn().mockResolvedValue([]),
    };
    const audioQueue: any = { add: jest.fn() };
    // Default config returns the second arg (the default), so the
    // service uses 20 / 2000. Individual tests can override.
    const configService: any = {
      get: jest.fn((_key: string, def?: any) => def),
    };
    const deepgramProvider: any = { transcribe: deepgramTranscribe };
    const aiClassifier: any = { classifyDistress: aiClassify };
    const incidentsService: any = { assertOwnership };
    const incidentGateway: any = { broadcastTimelineEvent };

    audioService = new (AudioService as any)(
      audioAssetRepo,
      transcriptRepo,
      audioQueue,
      configService,
      deepgramProvider,
      aiClassifier,
      incidentsService,
      incidentGateway,
    );
  });

  // ─────────────────────────────────────────────────────────────
  // 1. HAPPY PATH
  // ─────────────────────────────────────────────────────────────
  it('happy path: transcribes, classifies, persists, and broadcasts', async () => {
    deepgramTranscribe.mockResolvedValue({
      text: 'hello, are you ok?',
      confidence: 0.95,
      language: 'en',
    });
    aiClassify.mockResolvedValue({
      isDistress: false,
      riskLevel: 'none',
      confidence: 0.9,
      summary: 'normal conversation',
      signals: [],
    });

    await audioService.processTranscription(basePayload);

    // Ownership validated first
    expect(assertOwnership).toHaveBeenCalledWith(INCIDENT, USER);

    // Status went PENDING → PROCESSING → COMPLETED
    expect(assetUpdate).toHaveBeenCalledWith(ASSET, {
      transcriptionStatus: TranscriptionStatus.PROCESSING,
    });
    expect(assetUpdate).toHaveBeenCalledWith(ASSET, {
      transcriptionStatus: TranscriptionStatus.COMPLETED,
    });
    expect(assetUpdate).not.toHaveBeenCalledWith(ASSET, {
      transcriptionStatus: TranscriptionStatus.FAILED,
    });

    // External providers were both called
    expect(deepgramTranscribe).toHaveBeenCalled();
    expect(aiClassify).toHaveBeenCalledWith('hello, are you ok?', {
      incidentId: INCIDENT,
    });

    // Transcript persisted
    expect(transcriptSave).toHaveBeenCalledTimes(1);

    // Real-time broadcast emitted with correct event type
    expect(broadcastTimelineEvent).toHaveBeenCalledWith(
      INCIDENT,
      expect.objectContaining({ type: 'transcription_completed' }),
    );

    // No cost-cap path triggered
    expect(Sentry.captureMessage).not.toHaveBeenCalled();

    // Persistent timeline event recorded (createIncidentEvent uses
    // manager.query INSERT INTO incident_events)
    expect(managerQuery).toHaveBeenCalled();
  });

  // ─────────────────────────────────────────────────────────────
  // 2. COST CAP PER-INCIDENT
  // ─────────────────────────────────────────────────────────────
  it('cost cap per-incident: marks FAILED, skips Deepgram, does not throw', async () => {
    // Limit (default 20) already reached
    assetCount.mockResolvedValue(20);

    // Should resolve normally (no throw — BullMQ must NOT retry)
    await expect(
      audioService.processTranscription(basePayload),
    ).resolves.toBeUndefined();

    expect(assertOwnership).toHaveBeenCalled();

    // No external API calls
    expect(deepgramTranscribe).not.toHaveBeenCalled();
    expect(aiClassify).not.toHaveBeenCalled();

    // Status went PENDING → FAILED directly (never PROCESSING)
    expect(assetUpdate).toHaveBeenCalledWith(ASSET, {
      transcriptionStatus: TranscriptionStatus.FAILED,
    });
    expect(assetUpdate).not.toHaveBeenCalledWith(ASSET, {
      transcriptionStatus: TranscriptionStatus.PROCESSING,
    });

    // No real-time broadcast on cost cap
    expect(broadcastTimelineEvent).not.toHaveBeenCalled();

    // Sentry tagged with the right reason and ids
    expect(Sentry.captureMessage).toHaveBeenCalledWith(
      'cost_cap_hit',
      expect.objectContaining({
        level: 'warning',
        tags: {
          reason: 'per_incident',
          incidentId: INCIDENT,
          userId: USER,
          audioAssetId: ASSET,
        },
      }),
    );

    // incident_events row recorded with source='cost_cap'
    expect(managerQuery).toHaveBeenCalledWith(
      expect.stringContaining('incident_events'),
      expect.arrayContaining([
        INCIDENT,
        'ai_analysis_result',
        expect.stringContaining('cost_cap'),
      ]),
    );
  });

  // ─────────────────────────────────────────────────────────────
  // 3. COST CAP PER-DAY
  // ─────────────────────────────────────────────────────────────
  it('cost cap per-day: marks FAILED, skips Deepgram, does not throw', async () => {
    // Per-incident OK
    assetCount.mockResolvedValue(0);
    // Per-day total (last 24h) is at the limit (default 2000)
    dayMinutes.mockResolvedValue({ minutes: '2000.5' });

    await expect(
      audioService.processTranscription(basePayload),
    ).resolves.toBeUndefined();

    expect(deepgramTranscribe).not.toHaveBeenCalled();
    expect(aiClassify).not.toHaveBeenCalled();

    expect(assetUpdate).toHaveBeenCalledWith(ASSET, {
      transcriptionStatus: TranscriptionStatus.FAILED,
    });
    expect(assetUpdate).not.toHaveBeenCalledWith(ASSET, {
      transcriptionStatus: TranscriptionStatus.PROCESSING,
    });

    expect(broadcastTimelineEvent).not.toHaveBeenCalled();

    expect(Sentry.captureMessage).toHaveBeenCalledWith(
      'cost_cap_hit',
      expect.objectContaining({
        level: 'warning',
        tags: {
          reason: 'per_day',
          incidentId: INCIDENT,
          userId: USER,
          audioAssetId: ASSET,
        },
      }),
    );
  });

  // ─────────────────────────────────────────────────────────────
  // 4. OWNERSHIP FAIL (replayed/forged Redis payload)
  // ─────────────────────────────────────────────────────────────
  it('ownership fail: assertOwnership throws and exception propagates with no side effects', async () => {
    assertOwnership.mockRejectedValue(
      new NotFoundException('Incident not found'),
    );

    await expect(
      audioService.processTranscription(basePayload),
    ).rejects.toThrow(NotFoundException);

    // Nothing should have happened past the ownership check
    expect(deepgramTranscribe).not.toHaveBeenCalled();
    expect(aiClassify).not.toHaveBeenCalled();
    expect(assetUpdate).not.toHaveBeenCalled();
    expect(broadcastTimelineEvent).not.toHaveBeenCalled();
    expect(Sentry.captureMessage).not.toHaveBeenCalled();
  });

  // ─────────────────────────────────────────────────────────────
  // 5. DEEPGRAM ERROR (BullMQ retry path)
  // ─────────────────────────────────────────────────────────────
  it('Deepgram error: marks FAILED, rethrows for BullMQ retry', async () => {
    const apiError = new Error('Deepgram API timeout');
    deepgramTranscribe.mockRejectedValue(apiError);

    await expect(
      audioService.processTranscription(basePayload),
    ).rejects.toThrow('Deepgram API timeout');

    // PROCESSING transition happened (ownership + caps cleared)
    expect(assetUpdate).toHaveBeenCalledWith(ASSET, {
      transcriptionStatus: TranscriptionStatus.PROCESSING,
    });
    // Then FAILED in the catch block
    expect(assetUpdate).toHaveBeenCalledWith(ASSET, {
      transcriptionStatus: TranscriptionStatus.FAILED,
    });

    // Classifier never reached
    expect(aiClassify).not.toHaveBeenCalled();

    // No broadcast on failure
    expect(broadcastTimelineEvent).not.toHaveBeenCalled();

    // Cost-cap path NOT triggered (this is a normal error)
    expect(Sentry.captureMessage).not.toHaveBeenCalled();

    // ai_analysis_result event recorded with the error source
    expect(managerQuery).toHaveBeenCalledWith(
      expect.stringContaining('incident_events'),
      expect.arrayContaining([
        INCIDENT,
        'ai_analysis_result',
        expect.stringContaining('audio_transcription'),
      ]),
    );
  });
});
