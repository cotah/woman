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
 *      (no risk signal emitted when classifier returns no distress)
 *   2. Cost cap per-incident — abort before Deepgram, FAILED, no retry
 *   3. Cost cap per-day — abort before Deepgram, FAILED, no retry
 *   4. Ownership fail — assertOwnership throws, no side effects
 *   5. Deepgram error — PROCESSING → FAILED, rethrow for BullMQ retry
 *   6. Legacy payload — recovery via getOwnerUserId
 *   7. Distress without help_request — emits 1 risk signal
 *      (audio_distress_detected only)
 *   8. Distress with help_request — emits 2 risk signals
 *      (audio_distress_detected + help_phrase_detected)
 *   9. processRiskSignal throws — pipeline completes normally
 *      (logger.error, broadcast still emitted, no rethrow)
 *
 * Note on scope: tests validate that AudioService EMITS the right
 * signals to IncidentsService. Validation that the engine processes
 * them (or skips them in test mode) lives in
 * test/unit/risk-engine.spec.ts and is not repeated here.
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
  let getOwnerUserId: jest.Mock;
  let processRiskSignal: jest.Mock;
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
    getOwnerUserId = jest.fn().mockResolvedValue(USER);
    processRiskSignal = jest.fn().mockResolvedValue({});
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
    const incidentsService: any = {
      assertOwnership,
      getOwnerUserId,
      processRiskSignal,
    };
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

    // Bug 8.a — no risk signal emitted when classifier reports no
    // distress and no signals. The engine should not be touched at all.
    expect(processRiskSignal).not.toHaveBeenCalled();
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
  // 6. LEGACY PAYLOAD (no userId — enqueued before Fix 4)
  // ─────────────────────────────────────────────────────────────
  it('legacy payload: no userId — fallback recovers it from incident, skips assertOwnership, proceeds normally', async () => {
    deepgramTranscribe.mockResolvedValue({
      text: 'help me',
      confidence: 0.92,
      language: 'en',
    });
    aiClassify.mockResolvedValue({
      isDistress: false,
      riskLevel: 'none',
      confidence: 0.8,
      summary: 'recovered legacy payload',
      signals: [],
    });
    // Logger.warn observable on the service instance (private logger
    // is a Nest Logger, but its warn method is observable via spy).
    const warnSpy = jest
      .spyOn((audioService as any).logger, 'warn')
      .mockImplementation(() => undefined);

    // Build a payload without userId (the actual Sentry-reported case)
    const legacyPayload: any = {
      audioAssetId: ASSET,
      incidentId: INCIDENT,
      storageKey: STORAGE_KEY,
      mimeType: 'audio/webm',
    };

    await audioService.processTranscription(legacyPayload);

    // Fallback path: getOwnerUserId was used, assertOwnership was NOT
    expect(getOwnerUserId).toHaveBeenCalledWith(INCIDENT);
    expect(assertOwnership).not.toHaveBeenCalled();

    // Visible warning so monitoring can spot legacy payload recovery
    expect(warnSpy).toHaveBeenCalledWith(
      expect.stringContaining('[legacy-payload]'),
    );

    // Pipeline proceeds normally
    expect(assetUpdate).toHaveBeenCalledWith(ASSET, {
      transcriptionStatus: TranscriptionStatus.PROCESSING,
    });
    expect(assetUpdate).toHaveBeenCalledWith(ASSET, {
      transcriptionStatus: TranscriptionStatus.COMPLETED,
    });
    expect(deepgramTranscribe).toHaveBeenCalled();
    expect(aiClassify).toHaveBeenCalled();
    expect(transcriptSave).toHaveBeenCalledTimes(1);
    expect(broadcastTimelineEvent).toHaveBeenCalledWith(
      INCIDENT,
      expect.objectContaining({ type: 'transcription_completed' }),
    );

    // No cost-cap path triggered
    expect(Sentry.captureMessage).not.toHaveBeenCalled();
  });

  // ─────────────────────────────────────────────────────────────
  // 7. RISK SIGNAL — DISTRESS WITHOUT HELP REQUEST (Bug 8.a)
  // ─────────────────────────────────────────────────────────────
  it('emits audio_distress_detected only when classifier returns distress without help_request', async () => {
    deepgramTranscribe.mockResolvedValue({
      text: 'I am scared, please leave me alone',
      confidence: 0.93,
      language: 'en',
    });
    aiClassify.mockResolvedValue({
      isDistress: true,
      riskLevel: 'high',
      confidence: 0.88,
      summary: 'fear and verbal threat detected',
      signals: [
        {
          type: 'fear_indicator',
          description: 'expression of fear',
          confidence: 0.9,
          excerpt: 'I am scared',
        },
        {
          type: 'verbal_threat',
          description: 'implied threat',
          confidence: 0.7,
          excerpt: 'leave me alone',
        },
      ],
    });

    await audioService.processTranscription(basePayload);

    // Exactly one risk signal emitted: audio_distress_detected
    expect(processRiskSignal).toHaveBeenCalledTimes(1);
    expect(processRiskSignal).toHaveBeenCalledWith(
      INCIDENT,
      USER,
      expect.objectContaining({
        type: 'audio_distress_detected',
        payload: expect.objectContaining({
          audioAssetId: ASSET,
          riskLevel: 'high',
          confidence: 0.88,
          signalCount: 2,
        }),
      }),
    );

    // Pipeline still completes normally
    expect(transcriptSave).toHaveBeenCalledTimes(1);
    expect(broadcastTimelineEvent).toHaveBeenCalled();
  });

  // ─────────────────────────────────────────────────────────────
  // 8. RISK SIGNAL — DISTRESS WITH HELP REQUEST (Bug 8.a)
  // ─────────────────────────────────────────────────────────────
  it('emits audio_distress_detected AND help_phrase_detected when classifier finds help_request', async () => {
    deepgramTranscribe.mockResolvedValue({
      text: 'help me, please. he will kill me',
      confidence: 0.99,
      language: 'en',
    });
    aiClassify.mockResolvedValue({
      isDistress: true,
      riskLevel: 'critical',
      confidence: 0.97,
      summary: 'critical distress with explicit help request',
      signals: [
        {
          type: 'help_request',
          description: 'explicit plea for help',
          confidence: 0.99,
          excerpt: 'help me, please',
        },
        {
          type: 'violence_indicator',
          description: 'threat of homicide',
          confidence: 0.95,
          excerpt: 'he will kill me',
        },
        {
          type: 'help_request',
          description: 'second help plea',
          confidence: 0.88,
          excerpt: 'please',
        },
      ],
    });

    await audioService.processTranscription(basePayload);

    // Two distinct risk signals emitted, in order
    expect(processRiskSignal).toHaveBeenCalledTimes(2);
    expect(processRiskSignal).toHaveBeenNthCalledWith(
      1,
      INCIDENT,
      USER,
      expect.objectContaining({
        type: 'audio_distress_detected',
        payload: expect.objectContaining({
          audioAssetId: ASSET,
          signalCount: 3,
        }),
      }),
    );
    expect(processRiskSignal).toHaveBeenNthCalledWith(
      2,
      INCIDENT,
      USER,
      expect.objectContaining({
        type: 'help_phrase_detected',
        payload: expect.objectContaining({
          audioAssetId: ASSET,
          excerpts: expect.arrayContaining(['help me, please', 'please']),
        }),
      }),
    );

    expect(transcriptSave).toHaveBeenCalledTimes(1);
    expect(broadcastTimelineEvent).toHaveBeenCalled();
  });

  // ─────────────────────────────────────────────────────────────
  // 9. RISK SIGNAL — ENGINE THROWS (graceful degradation, Bug 8.a)
  // ─────────────────────────────────────────────────────────────
  it('completes pipeline normally when processRiskSignal throws (incident in terminal state)', async () => {
    deepgramTranscribe.mockResolvedValue({
      text: 'help me',
      confidence: 0.95,
      language: 'en',
    });
    aiClassify.mockResolvedValue({
      isDistress: true,
      riskLevel: 'high',
      confidence: 0.9,
      summary: 'distress',
      signals: [
        {
          type: 'help_request',
          description: 'plea',
          confidence: 0.95,
          excerpt: 'help me',
        },
      ],
    });
    // Simulate the common production case: incident transitioned to
    // a terminal status (cancelled/resolved) between transcription
    // start and end. processRiskSignal validates active status and
    // throws BadRequestException.
    const { BadRequestException } = require('@nestjs/common');
    processRiskSignal.mockRejectedValue(
      new BadRequestException(
        'Cannot process signals for incident in status "resolved".',
      ),
    );
    const errorSpy = jest
      .spyOn((audioService as any).logger, 'error')
      .mockImplementation(() => undefined);

    // Pipeline must complete without rethrowing
    await expect(
      audioService.processTranscription(basePayload),
    ).resolves.toBeUndefined();

    // Engine was attempted (first signal), threw on first call
    expect(processRiskSignal).toHaveBeenCalled();

    // Error logged at error level (not warn) per project decision
    // — terminal-state hits should be visible for pattern detection.
    expect(errorSpy).toHaveBeenCalledWith(
      expect.stringContaining('Failed to emit risk signal'),
      expect.any(String),
    );

    // Critical assertion: transcript was saved AND broadcast was
    // emitted. Pipeline did NOT abort on the signal failure.
    expect(transcriptSave).toHaveBeenCalledTimes(1);
    expect(broadcastTimelineEvent).toHaveBeenCalledWith(
      INCIDENT,
      expect.objectContaining({ type: 'transcription_completed' }),
    );

    // Asset still marked COMPLETED (not FAILED)
    expect(assetUpdate).toHaveBeenCalledWith(ASSET, {
      transcriptionStatus: TranscriptionStatus.COMPLETED,
    });
    expect(assetUpdate).not.toHaveBeenCalledWith(ASSET, {
      transcriptionStatus: TranscriptionStatus.FAILED,
    });
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
