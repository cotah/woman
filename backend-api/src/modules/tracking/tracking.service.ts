import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, MoreThan } from 'typeorm';
import { LocationSnapshot, LearnedPlace } from './tracking.entity';

@Injectable()
export class TrackingService {
  private readonly logger = new Logger(TrackingService.name);

  constructor(
    @InjectRepository(LocationSnapshot)
    private readonly snapshotRepo: Repository<LocationSnapshot>,
    @InjectRepository(LearnedPlace)
    private readonly placeRepo: Repository<LearnedPlace>,
  ) {}

  // ── Location Snapshots ──────────────────────────────

  /**
   * Record a single location snapshot.
   */
  async addSnapshot(
    userId: string,
    data: {
      latitude: number;
      longitude: number;
      accuracy?: number;
      timestamp?: string;
    },
  ): Promise<LocationSnapshot> {
    const snapshot = this.snapshotRepo.create({
      userId,
      latitude: data.latitude,
      longitude: data.longitude,
      accuracy: data.accuracy,
      timestamp: data.timestamp ? new Date(data.timestamp) : new Date(),
    });

    const saved = await this.snapshotRepo.save(snapshot);
    this.logger.debug(
      `Snapshot saved for user ${userId}: ${data.latitude},${data.longitude}`,
    );
    return saved;
  }

  /**
   * Record a batch of location snapshots.
   */
  async addSnapshotBatch(
    userId: string,
    locations: Array<{
      latitude: number;
      longitude: number;
      accuracy?: number;
      timestamp?: string;
    }>,
  ): Promise<number> {
    const entities = locations.map((loc) =>
      this.snapshotRepo.create({
        userId,
        latitude: loc.latitude,
        longitude: loc.longitude,
        accuracy: loc.accuracy,
        timestamp: loc.timestamp ? new Date(loc.timestamp) : new Date(),
      }),
    );

    await this.snapshotRepo.save(entities);
    this.logger.log(
      `Batch saved: ${entities.length} snapshots for user ${userId}`,
    );
    return entities.length;
  }

  /**
   * Get recent snapshots for a user.
   */
  async getSnapshots(
    userId: string,
    options?: { hours?: number; limit?: number },
  ): Promise<LocationSnapshot[]> {
    const hours = options?.hours ?? 24;
    const limit = options?.limit ?? 500;
    const since = new Date(Date.now() - hours * 60 * 60 * 1000);

    return this.snapshotRepo.find({
      where: { userId, timestamp: MoreThan(since) },
      order: { timestamp: 'DESC' },
      take: limit,
    });
  }

  /**
   * Get the latest snapshot for a user.
   */
  async getLatestSnapshot(userId: string): Promise<LocationSnapshot | null> {
    return this.snapshotRepo.findOne({
      where: { userId },
      order: { timestamp: 'DESC' },
    });
  }

  /**
   * Clean up old snapshots (keep last N days).
   */
  async pruneOldSnapshots(userId: string, keepDays: number = 90): Promise<number> {
    const cutoff = new Date(Date.now() - keepDays * 24 * 60 * 60 * 1000);
    const result = await this.snapshotRepo
      .createQueryBuilder()
      .delete()
      .where('user_id = :userId AND timestamp < :cutoff', { userId, cutoff })
      .execute();

    const deleted = result.affected ?? 0;
    if (deleted > 0) {
      this.logger.log(
        `Pruned ${deleted} old snapshots for user ${userId}`,
      );
    }
    return deleted;
  }

  // ── Learned Places ──────────────────────────────────

  /**
   * Get all learned places for a user.
   */
  async getPlaces(userId: string): Promise<LearnedPlace[]> {
    return this.placeRepo.find({
      where: { userId },
      order: { visitCount: 'DESC' },
    });
  }

  /**
   * Sync learned places from the mobile app.
   */
  async syncPlaces(
    userId: string,
    places: Array<{
      latitude: number;
      longitude: number;
      label?: string;
      autoLabel?: string;
      visitCount?: number;
      isConfirmedSafe?: boolean;
      isFlagged?: boolean;
      flagReason?: string;
      firstVisited?: string;
      lastVisited?: string;
      hourDistribution?: Record<string, number>;
      weekdayDistribution?: Record<string, number>;
    }>,
  ): Promise<number> {
    let count = 0;

    for (const placeData of places) {
      // Check if a place already exists near these coordinates
      const existing = await this.findNearbyPlace(
        userId,
        placeData.latitude,
        placeData.longitude,
        150, // 150m radius
      );

      if (existing) {
        // Update existing
        existing.visitCount = placeData.visitCount ?? existing.visitCount;
        existing.label = placeData.label ?? existing.label;
        existing.autoLabel = placeData.autoLabel ?? existing.autoLabel;
        existing.isConfirmedSafe =
          placeData.isConfirmedSafe ?? existing.isConfirmedSafe;
        existing.isFlagged = placeData.isFlagged ?? existing.isFlagged;
        existing.flagReason = placeData.flagReason ?? existing.flagReason;
        existing.lastVisited = placeData.lastVisited
          ? new Date(placeData.lastVisited)
          : existing.lastVisited;
        existing.hourDistribution =
          placeData.hourDistribution ?? existing.hourDistribution;
        existing.weekdayDistribution =
          placeData.weekdayDistribution ?? existing.weekdayDistribution;

        await this.placeRepo.save(existing);
      } else {
        // Create new
        const place = this.placeRepo.create({
          userId,
          latitude: placeData.latitude,
          longitude: placeData.longitude,
          label: placeData.label,
          autoLabel: placeData.autoLabel,
          visitCount: placeData.visitCount ?? 1,
          isConfirmedSafe: placeData.isConfirmedSafe ?? false,
          isFlagged: placeData.isFlagged ?? false,
          flagReason: placeData.flagReason,
          firstVisited: placeData.firstVisited
            ? new Date(placeData.firstVisited)
            : new Date(),
          lastVisited: placeData.lastVisited
            ? new Date(placeData.lastVisited)
            : new Date(),
          hourDistribution: placeData.hourDistribution,
          weekdayDistribution: placeData.weekdayDistribution,
        });
        await this.placeRepo.save(place);
      }
      count++;
    }

    this.logger.log(`Synced ${count} places for user ${userId}`);
    return count;
  }

  /**
   * Confirm a place as safe.
   */
  async confirmPlaceSafe(
    userId: string,
    placeId: string,
    label?: string,
  ): Promise<LearnedPlace | null> {
    const place = await this.placeRepo.findOne({
      where: { id: placeId, userId },
    });

    if (!place) return null;

    place.isConfirmedSafe = true;
    if (label) place.label = label;

    return this.placeRepo.save(place);
  }

  /**
   * Flag a place as unsafe.
   */
  async flagPlace(
    userId: string,
    placeId: string,
    reason?: string,
  ): Promise<LearnedPlace | null> {
    const place = await this.placeRepo.findOne({
      where: { id: placeId, userId },
    });

    if (!place) return null;

    place.isFlagged = true;
    place.isConfirmedSafe = false;
    place.flagReason = reason ?? null;

    return this.placeRepo.save(place);
  }

  // ── Private ─────────────────────────────────────────

  /**
   * Find an existing place within a radius (in meters) using Haversine.
   */
  private async findNearbyPlace(
    userId: string,
    lat: number,
    lng: number,
    radiusMeters: number,
  ): Promise<LearnedPlace | null> {
    // Use Haversine formula in SQL for efficient spatial query
    const places = await this.placeRepo
      .createQueryBuilder('p')
      .where('p.user_id = :userId', { userId })
      .andWhere(
        `(6371000 * acos(
          cos(radians(:lat)) * cos(radians(p.latitude)) *
          cos(radians(p.longitude) - radians(:lng)) +
          sin(radians(:lat)) * sin(radians(p.latitude))
        )) < :radius`,
        { lat, lng, radius: radiusMeters },
      )
      .orderBy(
        `(6371000 * acos(
          cos(radians(:lat)) * cos(radians(p.latitude)) *
          cos(radians(p.longitude) - radians(:lng)) +
          sin(radians(:lat)) * sin(radians(p.latitude))
        ))`,
        'ASC',
      )
      .setParameters({ lat, lng })
      .limit(1)
      .getMany();

    return places.length > 0 ? places[0] : null;
  }
}
