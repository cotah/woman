import {
  Controller,
  Post,
  Get,
  Delete,
  Param,
  Body,
  ParseUUIDPipe,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
} from '@nestjs/swagger';
import {
  CurrentUser,
  CurrentUserPayload,
} from '../../common/decorators/current-user.decorator';
import { JourneyService } from './journey.service';
import {
  CreateJourneyDto,
  ExtendJourneyDto,
  JourneyLocationDto,
} from './dto/create-journey.dto';

@ApiTags('Journey')
@ApiBearerAuth()
@Controller('journey')
export class JourneyController {
  constructor(private readonly journeyService: JourneyService) {}

  @Post()
  @ApiOperation({ summary: 'Start a new Safe Journey' })
  @ApiResponse({ status: 201, description: 'Journey created' })
  @ApiResponse({ status: 400, description: 'Active journey already exists' })
  async create(
    @CurrentUser() user: CurrentUserPayload,
    @Body() dto: CreateJourneyDto,
  ) {
    return this.journeyService.create(user.id, dto);
  }

  @Get('active')
  @ApiOperation({ summary: 'Get the current active journey' })
  @ApiResponse({ status: 200, description: 'Active journey returned, or { journey: null } if none' })
  async getActive(@CurrentUser() user: CurrentUserPayload) {
    const journey = await this.journeyService.getActive(user.id);
    // Explicit contract: always return 200 with { journey: <data|null> }.
    // Mobile client checks response.data['journey'] != null.
    // This avoids ambiguity between 404-not-found and no-active-journey.
    return { journey };
  }

  @Post(':id/checkin')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Extend journey duration (check-in)' })
  @ApiResponse({ status: 200, description: 'Journey extended' })
  async checkin(
    @CurrentUser() user: CurrentUserPayload,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ExtendJourneyDto,
  ) {
    return this.journeyService.checkin(id, user.id, dto);
  }

  @Post(':id/complete')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Manually complete a journey (arrived safely)' })
  @ApiResponse({ status: 200, description: 'Journey completed' })
  async complete(
    @CurrentUser() user: CurrentUserPayload,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.journeyService.complete(id, user.id);
  }

  @Post(':id/location')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Send location update and check for arrival' })
  @ApiResponse({ status: 200, description: 'Arrival check result' })
  async checkArrival(
    @CurrentUser() user: CurrentUserPayload,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: JourneyLocationDto,
  ) {
    return this.journeyService.checkArrival(id, user.id, dto);
  }

  @Post(':id/checkin-response')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Respond to safety check-in (ok or help)' })
  @ApiResponse({ status: 200, description: 'Response recorded' })
  async respondToCheckin(
    @CurrentUser() user: CurrentUserPayload,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: { response: 'ok' | 'help' },
  ) {
    return this.journeyService.respondToCheckin(id, user.id, body.response);
  }

  @Delete(':id')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Cancel an active journey' })
  @ApiResponse({ status: 200, description: 'Journey cancelled' })
  async cancel(
    @CurrentUser() user: CurrentUserPayload,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.journeyService.cancel(id, user.id);
  }
}
