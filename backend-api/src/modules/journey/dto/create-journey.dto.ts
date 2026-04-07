import { IsNumber, IsOptional, IsString, IsBoolean, Min, Max } from 'class-validator';

export class CreateJourneyDto {
  @IsNumber()
  destLatitude: number;

  @IsNumber()
  destLongitude: number;

  @IsOptional()
  @IsString()
  destLabel?: string;

  @IsNumber()
  @Min(5)
  @Max(480)
  durationMinutes: number;

  @IsOptional()
  @IsNumber()
  @Min(50)
  @Max(1000)
  arrivalRadiusMeters?: number;

  @IsOptional()
  @IsNumber()
  startLatitude?: number;

  @IsOptional()
  @IsNumber()
  startLongitude?: number;

  @IsOptional()
  @IsBoolean()
  isTestMode?: boolean;
}

export class ExtendJourneyDto {
  @IsNumber()
  @Min(5)
  @Max(120)
  additionalMinutes: number;
}

export class JourneyLocationDto {
  @IsNumber()
  latitude: number;

  @IsNumber()
  longitude: number;

  @IsOptional()
  @IsNumber()
  accuracy?: number;
}
