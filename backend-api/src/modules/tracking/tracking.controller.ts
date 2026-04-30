import {
  Controller,
  Post,
  Get,
  Patch,
  Body,
  Param,
  Query,
  Req,
  HttpCode,
  HttpStatus,
  BadRequestException,
  ParseUUIDPipe,
} from '@nestjs/common';
import { SkipThrottle } from '@nestjs/throttler';
import { TrackingService } from './tracking.service';
import { RequestWithUser } from '@/common/interfaces/request-context';

/**
 * Endpoints for 24/7 location tracking and learned places.
 *
 * All endpoints require JWT auth (global guard).
 * Tracking endpoints skip rate limiting since they're safety-critical.
 */
@Controller('location')
export class TrackingController {
  constructor(private readonly trackingService: TrackingService) {}

  // ── Location Snapshots ──────────────────────────────

  /**
   * Record a single location snapshot.
   * Called periodically by the mobile app's background tracker.
   */
  @Post('track')
  @HttpCode(HttpStatus.CREATED)
  @SkipThrottle()
  async addSnapshot(
    @Req() req: RequestWithUser,
    @Body()
    body: {
      latitude: number;
      longitude: number;
      accuracy?: number;
      timestamp?: string;
    },
  ) {
    this.validateCoordinates(body.latitude, body.longitude);

    const snapshot = await this.trackingService.addSnapshot(
      req.user.id,
      body,
    );

    return { id: snapshot.id, timestamp: snapshot.timestamp };
  }

  /**
   * Batch upload location snapshots.
   * Used for offline sync when the app regains connectivity.
   */
  @Post('track/batch')
  @HttpCode(HttpStatus.CREATED)
  @SkipThrottle()
  async addSnapshotBatch(
    @Req() req: RequestWithUser,
    @Body()
    body: {
      locations: Array<{
        latitude: number;
        longitude: number;
        accuracy?: number;
        timestamp?: string;
      }>;
    },
  ) {
    if (!body.locations || !Array.isArray(body.locations)) {
      throw new BadRequestException('locations array is required');
    }
    if (body.locations.length > 500) {
      throw new BadRequestException('Maximum 500 locations per batch');
    }

    for (const loc of body.locations) {
      this.validateCoordinates(loc.latitude, loc.longitude);
    }

    const count = await this.trackingService.addSnapshotBatch(
      req.user.id,
      body.locations,
    );

    return { count };
  }

  /**
   * Get recent location snapshots.
   */
  @Get('track')
  async getSnapshots(
    @Req() req: RequestWithUser,
    @Query('hours') hours?: string,
    @Query('limit') limit?: string,
  ) {
    const snapshots = await this.trackingService.getSnapshots(
      req.user.id,
      {
        hours: hours ? parseInt(hours, 10) : 24,
        limit: limit ? parseInt(limit, 10) : 500,
      },
    );

    return { count: snapshots.length, snapshots };
  }

  /**
   * Get the latest location snapshot.
   */
  @Get('track/latest')
  async getLatestSnapshot(@Req() req: RequestWithUser) {
    const snapshot = await this.trackingService.getLatestSnapshot(
      req.user.id,
    );

    return snapshot ?? { message: 'No location data available' };
  }

  // ── Learned Places ──────────────────────────────────

  /**
   * Get all learned places for the current user.
   */
  @Get('places')
  async getPlaces(@Req() req: RequestWithUser) {
    const places = await this.trackingService.getPlaces(
      req.user.id,
    );

    return { count: places.length, places };
  }

  /**
   * Sync learned places from mobile app to backend.
   */
  @Post('places/sync')
  @HttpCode(HttpStatus.OK)
  async syncPlaces(
    @Req() req: RequestWithUser,
    @Body()
    body: {
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
      }>;
    },
  ) {
    if (!body.places || !Array.isArray(body.places)) {
      throw new BadRequestException('places array is required');
    }

    const count = await this.trackingService.syncPlaces(
      req.user.id,
      body.places,
    );

    return { synced: count };
  }

  /**
   * Confirm a place as safe.
   */
  @Patch('places/:id/safe')
  async confirmPlaceSafe(
    @Req() req: RequestWithUser,
    @Param('id', ParseUUIDPipe) placeId: string,
    @Body() body: { label?: string },
  ) {
    const place = await this.trackingService.confirmPlaceSafe(
      req.user.id,
      placeId,
      body.label,
    );

    if (!place) {
      throw new BadRequestException('Place not found');
    }

    return place;
  }

  /**
   * Flag a place as unsafe.
   */
  @Patch('places/:id/flag')
  async flagPlace(
    @Req() req: RequestWithUser,
    @Param('id', ParseUUIDPipe) placeId: string,
    @Body() body: { reason?: string },
  ) {
    const place = await this.trackingService.flagPlace(
      req.user.id,
      placeId,
      body.reason,
    );

    if (!place) {
      throw new BadRequestException('Place not found');
    }

    return place;
  }

  // ── Geofence Events ─────────────────────────────────

  /**
   * Log a geofence event (entry or exit).
   * Called by the mobile app when a geofence boundary is crossed.
   */
  @Post('geofence/events')
  @HttpCode(HttpStatus.CREATED)
  async logGeofenceEvent(
    @Req() req: RequestWithUser,
    @Body()
    body: {
      zoneId: string;
      zoneName: string;
      event: 'entered' | 'exited';
      latitude: number;
      longitude: number;
      radiusMeters?: number;
      zoneType?: string;
      timestamp?: string;
    },
  ) {
    if (!body.zoneId || !body.zoneName || !body.event) {
      throw new BadRequestException(
        'zoneId, zoneName, and event are required',
      );
    }
    if (!['entered', 'exited'].includes(body.event)) {
      throw new BadRequestException('event must be "entered" or "exited"');
    }

    this.validateCoordinates(body.latitude, body.longitude);

    // Store as a location snapshot with geofence metadata
    const snapshot = await this.trackingService.addSnapshot(
      req.user.id,
      {
        latitude: body.latitude,
        longitude: body.longitude,
        timestamp: body.timestamp,
      },
    );

    return {
      id: snapshot.id,
      event: body.event,
      zone: body.zoneName,
      timestamp: snapshot.timestamp,
    };
  }

  // ── Validation ──────────────────────────────────────

  private validateCoordinates(lat: number, lng: number) {
    if (lat == null || lng == null) {
      throw new BadRequestException('latitude and longitude are required');
    }
    if (lat < -90 || lat > 90) {
      throw new BadRequestException('latitude must be between -90 and 90');
    }
    if (lng < -180 || lng > 180) {
      throw new BadRequestException('longitude must be between -180 and 180');
    }
  }
}
