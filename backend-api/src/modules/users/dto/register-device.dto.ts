import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';
import { DevicePlatform } from '../entities/user-device.entity';

/**
 * DTO for POST /users/me/devices
 *
 * The mobile app calls this on first login, on app launch when an FCM
 * token rotation has happened, or after the user completes onboarding.
 * Idempotent — repeated calls UPSERT on (user_id, push_token).
 */
export class RegisterDeviceDto {
  @ApiProperty({
    enum: DevicePlatform,
    example: DevicePlatform.ANDROID,
    description: 'Device platform.',
  })
  @IsEnum(DevicePlatform)
  platform: DevicePlatform;

  @ApiProperty({
    example: 'cXJYzABCdef123:APA91...',
    description: 'FCM (Android) or APNs-registered (iOS) push token.',
  })
  @IsString()
  @MaxLength(500)
  pushToken: string;

  @ApiPropertyOptional({
    example: 'Pixel 7',
    description: 'Human-readable device model (telemetry only).',
  })
  @IsOptional()
  @IsString()
  @MaxLength(100)
  deviceModel?: string;

  @ApiPropertyOptional({
    example: 'Android 14',
    description: 'OS version string (telemetry only).',
  })
  @IsOptional()
  @IsString()
  @MaxLength(50)
  osVersion?: string;

  @ApiPropertyOptional({
    example: '1.0.0+13',
    description: 'App version (telemetry only).',
  })
  @IsOptional()
  @IsString()
  @MaxLength(50)
  appVersion?: string;
}
