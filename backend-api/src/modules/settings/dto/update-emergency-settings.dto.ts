import {
  IsString,
  IsOptional,
  IsInt,
  IsBoolean,
  IsEnum,
  IsArray,
  IsUUID,
  Min,
  Max,
  MaxLength,
  IsObject,
} from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';
import { AudioConsentLevel, RiskLevel } from '../entities/emergency-settings.entity';

export class UpdateEmergencySettingsDto {
  @ApiPropertyOptional({ example: 5, minimum: 3, maximum: 30 })
  @IsOptional()
  @IsInt()
  @Min(3)
  @Max(30)
  countdownDurationSeconds?: number;

  @ApiPropertyOptional({ example: 'tap_pattern', maxLength: 50 })
  @IsOptional()
  @IsString()
  @MaxLength(50)
  normalCancelMethod?: string;

  @ApiPropertyOptional({ enum: AudioConsentLevel })
  @IsOptional()
  @IsEnum(AudioConsentLevel)
  audioConsent?: AudioConsentLevel;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  autoRecordAudio?: boolean;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  allowAiAnalysis?: boolean;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  shareAudioWithContacts?: boolean;

  @ApiPropertyOptional({ type: [String], example: [] })
  @IsOptional()
  @IsArray()
  @IsUUID('4', { each: true })
  audioContactIds?: string[];

  @ApiPropertyOptional({ enum: RiskLevel })
  @IsOptional()
  @IsEnum(RiskLevel)
  audioShareThreshold?: RiskLevel;

  @ApiPropertyOptional({ default: false })
  @IsOptional()
  @IsBoolean()
  enableTestMode?: boolean;

  @ApiPropertyOptional({ type: 'array', example: [] })
  @IsOptional()
  @IsArray()
  triggerConfigurations?: Record<string, any>[];

  @ApiPropertyOptional({ example: 'I need help. This is an emergency alert from SafeCircle.' })
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  emergencyMessage?: string;
}
