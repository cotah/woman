import { IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { ContactResponseType } from '../entities/contact-response.entity';

export class ContactRespondDto {
  @ApiProperty({
    enum: [
      'trying_to_reach',
      'could_not_reach',
      'going_to_location',
      'calling_authorities',
      'marked_reviewed',
    ],
    description: 'Type of response from the trusted contact',
  })
  @IsEnum([
    'trying_to_reach',
    'could_not_reach',
    'going_to_location',
    'calling_authorities',
    'marked_reviewed',
  ])
  responseType: ContactResponseType;

  @ApiPropertyOptional({
    description: 'Optional note from the contact',
    maxLength: 2000,
  })
  @IsOptional()
  @IsString()
  @MaxLength(2000)
  note?: string;
}
