import { NotFoundException } from '@nestjs/common';
import { AudioService } from '../../src/modules/audio/audio.service';
import { LocationService } from '../../src/modules/location/location.service';

/**
 * IDOR test — B2.
 *
 * Confirms that AudioService and LocationService refuse to operate on
 * an incident the calling user does not own, by delegating ownership
 * validation to IncidentsService.assertOwnership.
 *
 * Threat model: the JWT guard already authenticates the caller. What's
 * missing today is per-resource ownership: user B authenticated with
 * a valid token can hit `POST /incidents/{A-id}/location` and the
 * service blindly writes to user A's incident.
 *
 * BEFORE the fix (state of `main` when this spec was first written):
 *   all 7 scenarios FAIL — services accept the call and produce side
 *   effects (S3 uploads, DB rows, queue jobs) on another user's data.
 *
 * AFTER the fix:
 *   all 7 scenarios PASS — services call assertOwnership first, which
 *   throws NotFoundException (unified error per the existence-leak fix).
 *
 * Refs: docs/AUDITORIA_2026-04-28.md item B2.
 */

// S3 client and presigner are stubbed at module-load time so the
// services don't try to reach a real bucket during construction.
jest.mock('@aws-sdk/client-s3', () => ({
  S3Client: jest.fn().mockImplementation(() => ({
    send: jest.fn().mockResolvedValue({}),
  })),
  PutObjectCommand: jest.fn(),
  GetObjectCommand: jest.fn(),
}));
jest.mock('@aws-sdk/s3-request-presigner', () => ({
  getSignedUrl: jest.fn().mockResolvedValue('https://signed.example/x'),
}));

describe('IDOR — audio + location ownership (B2)', () => {
  const USER_A = '11111111-1111-1111-1111-111111111111';
  const USER_B = '22222222-2222-2222-2222-222222222222';
  const A_INCIDENT_ID = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  const A_AUDIO_ASSET_ID = 'cccccccc-cccc-cccc-cccc-cccccccccccc';

  let audioService: AudioService;
  let locationService: LocationService;
  let assertOwnership: jest.Mock;

  beforeEach(() => {
    // Pretend the DB has one incident, owned by user A.
    const mockIncidentRepo = {
      findOne: jest.fn().mockImplementation(({ where }: any) => {
        if (where.id === A_INCIDENT_ID) {
          return Promise.resolve({ id: A_INCIDENT_ID, userId: USER_A });
        }
        return Promise.resolve(null);
      }),
    };

    // Stand-in for IncidentsService.assertOwnership. Mirrors the real
    // implementation in src/modules/incidents/incidents.service.ts:
    //   - throws NotFoundException if the incident is missing
    //   - throws NotFoundException if it belongs to another user
    // (see commit 038340a — unified to 404 to prevent existence leak).
    assertOwnership = jest.fn(
      async (incidentId: string, userId: string): Promise<void> => {
        const incident = await mockIncidentRepo.findOne({
          where: { id: incidentId },
        });
        if (!incident || incident.userId !== userId) {
          throw new NotFoundException(`Incident ${incidentId} not found`);
        }
      },
    );
    const incidentsServiceStub: any = { assertOwnership };

    // ─── AudioService dependencies ──────────────────────────────
    // The findOne mock has to be tuned so that, *in the current
    // vulnerable state*, every audio service method runs to completion
    // and returns success. That's what makes a failing IDOR test prove
    // the vulnerability instead of accidentally passing because some
    // unrelated lookup happened to return null.
    //   - asset lookup ({where:{id}})         → return a valid asset
    //   - last-chunk lookup ({where:{incidentId}}) → return null
    const audioAssetRepo: any = {
      findOne: jest.fn().mockImplementation(({ where }: any) => {
        if (where?.id) {
          return Promise.resolve({
            id: where.id,
            incidentId: A_INCIDENT_ID,
            storageKey: 'incidents/A/audio/chunk_0000.webm',
          });
        }
        return Promise.resolve(null);
      }),
      find: jest.fn().mockResolvedValue([]),
      create: jest.fn((d) => ({ id: 'new-asset', ...d })),
      save: jest.fn(async (d) => ({ id: 'new-asset', ...d })),
      update: jest.fn().mockResolvedValue(undefined),
      manager: { query: jest.fn().mockResolvedValue(undefined) },
    };
    const transcriptRepo: any = {
      find: jest.fn().mockResolvedValue([]),
    };
    const audioQueue: any = { add: jest.fn().mockResolvedValue(undefined) };
    const configService: any = { get: jest.fn((_k: string, def?: any) => def) };
    const deepgramProvider: any = { transcribe: jest.fn() };
    const aiClassifier: any = { classifyDistress: jest.fn() };

    // The 7th constructor arg (incidentsServiceStub) is what the B2
    // fix will introduce. Today the constructor ignores extra args.
    audioService = new (AudioService as any)(
      audioAssetRepo,
      transcriptRepo,
      audioQueue,
      configService,
      deepgramProvider,
      aiClassifier,
      incidentsServiceStub,
    );

    // ─── LocationService dependencies ───────────────────────────
    const locationQueryBuilder: any = {
      where: jest.fn().mockReturnThis(),
      andWhere: jest.fn().mockReturnThis(),
      orderBy: jest.fn().mockReturnThis(),
      limit: jest.fn().mockReturnThis(),
      getMany: jest.fn().mockResolvedValue([]),
    };
    const locationRepo: any = {
      create: jest.fn((d) => ({ id: 'new-loc', ...d })),
      save: jest.fn(async (d) => ({ id: 'new-loc', ...d })),
      findOne: jest.fn().mockResolvedValue(null),
      createQueryBuilder: jest.fn(() => locationQueryBuilder),
      manager: { query: jest.fn().mockResolvedValue(undefined) },
    };

    locationService = new (LocationService as any)(
      locationRepo,
      incidentsServiceStub,
    );
  });

  // ─────────────────────────────────────────────────────────────
  // AUDIO — 4 scenarios
  // ─────────────────────────────────────────────────────────────
  describe('audio endpoints — user B targets user A incident', () => {
    const fakeFile = {
      buffer: Buffer.from('fake-audio-bytes'),
      size: 16,
      mimetype: 'audio/webm',
    } as any;

    it('POST /incidents/:id/audio — uploadChunk must reject with 404', async () => {
      await expect(
        (audioService as any).uploadChunk(A_INCIDENT_ID, USER_B, fakeFile, 30),
      ).rejects.toThrow(NotFoundException);
    });

    it('GET /incidents/:id/audio — listChunks must reject with 404', async () => {
      await expect(
        (audioService as any).listChunks(A_INCIDENT_ID, USER_B),
      ).rejects.toThrow(NotFoundException);
    });

    it('GET /incidents/:id/audio/:assetId/download — getDownloadUrl must reject with 404', async () => {
      await expect(
        (audioService as any).getDownloadUrl(
          A_INCIDENT_ID,
          USER_B,
          A_AUDIO_ASSET_ID,
        ),
      ).rejects.toThrow(NotFoundException);
    });

    it('GET /incidents/:id/transcripts — getTranscripts must reject with 404', async () => {
      await expect(
        (audioService as any).getTranscripts(A_INCIDENT_ID, USER_B),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // LOCATION — 3 scenarios
  // ─────────────────────────────────────────────────────────────
  describe('location endpoints — user B targets user A incident', () => {
    const dto: any = { latitude: -23.5, longitude: -46.6 };

    it('POST /incidents/:id/location — addLocation must reject with 404', async () => {
      await expect(
        (locationService as any).addLocation(A_INCIDENT_ID, USER_B, dto),
      ).rejects.toThrow(NotFoundException);
    });

    it('POST /incidents/:id/location/batch — addLocation per entry must reject with 404', async () => {
      // Controller-level batch loops over entries; the service-level
      // ownership check fires on the first entry.
      await expect(
        (locationService as any).addLocation(A_INCIDENT_ID, USER_B, dto),
      ).rejects.toThrow(NotFoundException);
    });

    it('GET /incidents/:id/locations — getLocationTrail must reject with 404', async () => {
      await expect(
        (locationService as any).getLocationTrail(A_INCIDENT_ID, USER_B),
      ).rejects.toThrow(NotFoundException);
    });
  });

  // ─────────────────────────────────────────────────────────────
  // CONTROL — same calls succeed for the legitimate owner
  // ─────────────────────────────────────────────────────────────
  describe('sanity check — owner can still operate on their own incident', () => {
    it('addLocation works for user A (proves the rejection above is ownership-driven, not a generic block)', async () => {
      // This call must NOT throw. If after the B2 fix this starts
      // failing, the assertOwnership signature got wired incorrectly.
      await expect(
        (locationService as any).addLocation(A_INCIDENT_ID, USER_A, {
          latitude: -23.5,
          longitude: -46.6,
        }),
      ).resolves.toBeDefined();
    });
  });
});
