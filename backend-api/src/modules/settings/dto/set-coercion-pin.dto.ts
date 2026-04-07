import { IsString, Length, Matches } from 'class-validator';
import { ApiProperty } from '@nestjs/swagger';

export class SetCoercionPinDto {
  @ApiProperty({
    description: 'A 4-6 digit PIN used under coercion to silently trigger a real alert',
    example: '9911',
    minLength: 4,
    maxLength: 6,
  })
  @IsString()
  @Length(4, 6)
  @Matches(/^\d{4,6}$/, { message: 'Coercion PIN must be 4-6 digits' })
  pin: string;
}
