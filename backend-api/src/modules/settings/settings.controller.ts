import {
  Controller,
  Get,
  Patch,
  Post,
  Body,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import {
  ApiTags,
  ApiBearerAuth,
  ApiOperation,
  ApiResponse,
} from '@nestjs/swagger';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { AuthenticatedUser } from '../../common/interfaces/request-context';
import { SettingsService } from './settings.service';
import { UpdateEmergencySettingsDto } from './dto/update-emergency-settings.dto';
import { SetCoercionPinDto } from './dto/set-coercion-pin.dto';
import { EmergencySettings } from './entities/emergency-settings.entity';

@ApiTags('Settings')
@ApiBearerAuth()
// Auth: protected by global APP_GUARD (JwtAuthGuard) registered in app.module.ts
@Controller('settings')
export class SettingsController {
  constructor(private readonly settingsService: SettingsService) {}

  @Get('emergency')
  @ApiOperation({ summary: 'Get emergency settings for the current user' })
  @ApiResponse({ status: 200, description: 'Emergency settings returned (auto-created if first access)' })
  async getEmergencySettings(
    @CurrentUser() user: AuthenticatedUser,
  ): Promise<EmergencySettings> {
    return this.settingsService.getEmergencySettings(user.id);
  }

  @Patch('emergency')
  @ApiOperation({ summary: 'Update emergency settings' })
  @ApiResponse({ status: 200, description: 'Emergency settings updated' })
  async updateEmergencySettings(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: UpdateEmergencySettingsDto,
  ): Promise<EmergencySettings> {
    return this.settingsService.updateEmergencySettings(user.id, dto);
  }

  @Post('emergency/coercion-pin')
  @HttpCode(HttpStatus.NO_CONTENT)
  @ApiOperation({ summary: 'Set or update the coercion PIN (hashed, never returned)' })
  @ApiResponse({ status: 204, description: 'Coercion PIN saved' })
  async setCoercionPin(
    @CurrentUser() user: AuthenticatedUser,
    @Body() dto: SetCoercionPinDto,
  ): Promise<void> {
    await this.settingsService.setCoercionPin(user.id, dto.pin);
  }
}
