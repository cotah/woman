import { IsString, IsOptional, IsBoolean } from 'class-validator';
import { ApiPropertyOptional } from '@nestjs/swagger';

export class ResolveIncidentDto {
  @ApiPropertyOptional({ description: 'Reason for resolving the incident' })
  @IsOptional()
  @IsString()
  reason?: string;

  @ApiPropertyOptional({
    description: 'If true, marks the incident as a false alarm',
    default: false,
  })
  @IsOptional()
  @IsBoolean()
  isFalseAlarm?: boolean;
}

export class CancelIncidentDto {
  @ApiPropertyOptional({
    description:
      'If true, this is a secret cancel via coercion PIN - UI shows cancelled but backend escalates',
    default: false,
  })
  @IsOptional()
  @IsBoolean()
  isSecretCancel?: boolean;

  @ApiPropertyOptional({ description: 'Reason for cancellation' })
  @IsOptional()
  @IsString()
  reason?: string;
}

export class AddEventDto {
  @ApiPropertyOptional({ description: 'Event type' })
  @IsString()
  type: string;

  @ApiPropertyOptional({ description: 'Event payload data' })
  @IsOptional()
  payload?: Record<string, any>;

  @ApiPropertyOptional({ description: 'Event source identifier' })
  @IsOptional()
  @IsString()
  source?: string;
}
