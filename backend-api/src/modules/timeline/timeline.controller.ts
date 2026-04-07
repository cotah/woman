import {
  Controller,
  Get,
  Param,
  Query,
  UseGuards,
  ParseUUIDPipe,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBearerAuth,
  ApiQuery,
} from '@nestjs/swagger';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import {
  CurrentUser,
  CurrentUserPayload,
} from '../../common/decorators/current-user.decorator';
import { TimelineService } from './timeline.service';

@ApiTags('Timeline')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('incidents/:id/timeline')
export class TimelineController {
  constructor(private readonly timelineService: TimelineService) {}

  @Get()
  @ApiOperation({
    summary: 'Get a unified chronological timeline for an incident',
  })
  @ApiResponse({
    status: 200,
    description: 'Sorted array of timeline entries (events, locations, risk changes)',
  })
  @ApiResponse({ status: 404, description: 'Incident not found' })
  @ApiQuery({
    name: 'includeInternal',
    required: false,
    type: Boolean,
    description: 'Include internal/system-only events (admin use)',
  })
  async getTimeline(
    @CurrentUser() user: CurrentUserPayload,
    @Param('id', ParseUUIDPipe) id: string,
    @Query('includeInternal') includeInternal?: string,
  ) {
    return this.timelineService.getTimeline(
      id,
      user.id,
      includeInternal === 'true',
    );
  }
}
