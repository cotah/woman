import {
  Controller,
  Post,
  Get,
  Param,
  Body,
  Query,
  ParseUUIDPipe,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiParam,
  ApiResponse,
  ApiQuery,
  ApiBearerAuth,
} from '@nestjs/swagger';
import { SkipThrottle } from '@nestjs/throttler';
import {
  IsNumber,
  IsOptional,
  IsString,
  Min,
  Max,
  IsDateString,
} from 'class-validator';
import { Type } from 'class-transformer';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { LocationService } from './location.service';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { AuthenticatedUser } from '../../common/interfaces/request-context';

export class CreateLocationDto {
  @ApiProperty({ description: 'Latitude', example: 48.8566 })
  @IsNumber()
  @Min(-90)
  @Max(90)
  @Type(() => Number)
  latitude: number;

  @ApiProperty({ description: 'Longitude', example: 2.3522 })
  @IsNumber()
  @Min(-180)
  @Max(180)
  @Type(() => Number)
  longitude: number;

  @ApiPropertyOptional({ description: 'Accuracy in meters' })
  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  accuracy?: number;

  @ApiPropertyOptional({ description: 'Speed in m/s' })
  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  speed?: number;

  @ApiPropertyOptional({ description: 'Heading in degrees (0-360)' })
  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  heading?: number;

  @ApiPropertyOptional({ description: 'Altitude in meters' })
  @IsOptional()
  @IsNumber()
  @Type(() => Number)
  altitude?: number;

  @ApiPropertyOptional({
    description: 'Location provider (gps, network, fused)',
  })
  @IsOptional()
  @IsString()
  provider?: string;

  @ApiPropertyOptional({
    description: 'Client-side timestamp (ISO 8601)',
    example: '2026-04-06T12:00:00Z',
  })
  @IsOptional()
  @IsDateString()
  timestamp?: string;
}

@ApiTags('Location')
@ApiBearerAuth()
@SkipThrottle() // Safety-critical: location updates during emergencies must never be blocked
@Controller('incidents')
export class LocationController {
  constructor(private readonly locationService: LocationService) {}

  /**
   * POST /incidents/:id/location
   * Record a location update for an incident.
   */
  @Post(':id/location')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Record a location update for an incident' })
  @ApiParam({ name: 'id', description: 'Incident ID', type: 'string' })
  @ApiResponse({ status: 201, description: 'Location recorded' })
  async addLocation(
    @Param('id', ParseUUIDPipe) incidentId: string,
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: CreateLocationDto,
  ) {
    const location = await this.locationService.addLocation(
      incidentId,
      user.id,
      dto,
    );

    return {
      id: location.id,
      incidentId: location.incidentId,
      latitude: location.latitude,
      longitude: location.longitude,
      accuracy: location.accuracy,
      speed: location.speed,
      heading: location.heading,
      altitude: location.altitude,
      provider: location.provider,
      timestamp: location.timestamp,
    };
  }

  /**
   * POST /incidents/:id/location/batch
   * Record multiple queued location updates at once (offline sync).
   */
  @Post(':id/location/batch')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({ summary: 'Batch upload location updates (offline sync)' })
  @ApiParam({ name: 'id', description: 'Incident ID', type: 'string' })
  @ApiResponse({ status: 201, description: 'Locations recorded' })
  async addLocationBatch(
    @Param('id', ParseUUIDPipe) incidentId: string,
    @CurrentUser() user: AuthenticatedUser,
    @Body() dtos: CreateLocationDto[],
  ) {
    const results = [];
    for (const dto of dtos) {
      const location = await this.locationService.addLocation(
        incidentId,
        user.id,
        dto,
      );
      results.push({
        id: location.id,
        latitude: location.latitude,
        longitude: location.longitude,
        timestamp: location.timestamp,
      });
    }
    return { count: results.length, locations: results };
  }

  /**
   * GET /incidents/:id/locations
   * Get the location trail for an incident.
   */
  @Get(':id/locations')
  @ApiOperation({ summary: 'Get the location trail for an incident' })
  @ApiParam({ name: 'id', description: 'Incident ID', type: 'string' })
  @ApiQuery({ name: 'limit', required: false, type: Number })
  @ApiQuery({
    name: 'since',
    required: false,
    type: String,
    description: 'ISO 8601 timestamp to filter locations after',
  })
  @ApiResponse({ status: 200, description: 'Location trail' })
  async getLocations(
    @Param('id', ParseUUIDPipe) incidentId: string,
    @CurrentUser() user: AuthenticatedUser,
    @Query('limit') limitStr?: string,
    @Query('since') sinceStr?: string,
  ) {
    const limit = limitStr ? parseInt(limitStr, 10) : undefined;
    const since = sinceStr ? new Date(sinceStr) : undefined;

    const locations = await this.locationService.getLocationTrail(
      incidentId,
      user.id,
      { limit, since },
    );

    return locations.map((loc) => ({
      id: loc.id,
      latitude: loc.latitude,
      longitude: loc.longitude,
      accuracy: loc.accuracy,
      speed: loc.speed,
      heading: loc.heading,
      altitude: loc.altitude,
      provider: loc.provider,
      timestamp: loc.timestamp,
    }));
  }
}
