import {
  IsEnum,
  IsBoolean,
  IsOptional,
  IsNumber,
  IsString,
  ValidateNested,
  Min,
  Max,
} from 'class-validator';
import { Type } from 'class-transformer';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { TriggerType } from '../entities/incident.entity';

export class LocationDto {
  @ApiProperty({ example: 48.8566 })
  @IsNumber()
  @Min(-90)
  @Max(90)
  latitude: number;

  @ApiProperty({ example: 2.3522 })
  @IsNumber()
  @Min(-180)
  @Max(180)
  longitude: number;

  @ApiPropertyOptional({ example: 10.5 })
  @IsOptional()
  @IsNumber()
  accuracy?: number;

  @ApiPropertyOptional({ example: 1.2 })
  @IsOptional()
  @IsNumber()
  speed?: number;

  @ApiPropertyOptional({ example: 180.0 })
  @IsOptional()
  @IsNumber()
  heading?: number;

  @ApiPropertyOptional({ example: 35.0 })
  @IsOptional()
  @IsNumber()
  altitude?: number;

  @ApiPropertyOptional({ example: 'gps' })
  @IsOptional()
  @IsString()
  provider?: string;
}

export class CreateIncidentDto {
  @ApiProperty({ enum: TriggerType, example: TriggerType.MANUAL_BUTTON })
  @IsEnum(TriggerType)
  triggerType: TriggerType;

  @ApiPropertyOptional({
    description: 'If true, the incident was triggered with the coercion PIN',
    default: false,
  })
  @IsOptional()
  @IsBoolean()
  isCoercion?: boolean;

  @ApiPropertyOptional({
    description: 'If true, this is a test/drill incident that will not notify contacts',
    default: false,
  })
  @IsOptional()
  @IsBoolean()
  isTestMode?: boolean;

  @ApiPropertyOptional({ description: 'Initial location when trigger was activated' })
  @IsOptional()
  @ValidateNested()
  @Type(() => LocationDto)
  location?: LocationDto;

  @ApiPropertyOptional({
    description: 'Countdown duration in seconds (overrides user settings)',
  })
  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(30)
  countdownSeconds?: number;
}
