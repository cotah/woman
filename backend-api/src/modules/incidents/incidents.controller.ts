import {
  Controller,
  Post,
  Get,
  Param,
  Body,
  Query,
  UseGuards,
  ParseUUIDPipe,
  HttpCode,
  HttpStatus,
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
import { IncidentsService, IncidentFilters } from './incidents.service';
import { CreateIncidentDto } from './dto/create-incident.dto';
import {
  ResolveIncidentDto,
  CancelIncidentDto,
  AddEventDto,
} from './dto/resolve-incident.dto';
import { IncidentStatus, TriggerType } from './entities/incident.entity';

@ApiTags('Incidents')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('incidents')
export class IncidentsController {
  constructor(private readonly incidentsService: IncidentsService) {}

  @Post()
  @ApiOperation({ summary: 'Create a new incident from a trigger activation' })
  @ApiResponse({ status: 201, description: 'Incident created and countdown started' })
  @ApiResponse({ status: 400, description: 'Active incident already exists' })
  async create(
    @CurrentUser() user: CurrentUserPayload,
    @Body() dto: CreateIncidentDto,
  ) {
    return this.incidentsService.create(user.id, dto);
  }

  @Get()
  @ApiOperation({ summary: 'List incidents with pagination and filters' })
  @ApiQuery({ name: 'page', required: false, type: Number })
  @ApiQuery({ name: 'limit', required: false, type: Number })
  @ApiQuery({ name: 'status', required: false, enum: IncidentStatus })
  @ApiQuery({ name: 'triggerType', required: false, enum: TriggerType })
  @ApiQuery({ name: 'isTestMode', required: false, type: Boolean })
  @ApiQuery({ name: 'from', required: false, type: String, description: 'ISO date' })
  @ApiQuery({ name: 'to', required: false, type: String, description: 'ISO date' })
  async findAll(
    @CurrentUser() user: CurrentUserPayload,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
    @Query('status') status?: IncidentStatus,
    @Query('triggerType') triggerType?: TriggerType,
    @Query('isTestMode') isTestMode?: string,
    @Query('from') from?: string,
    @Query('to') to?: string,
  ) {
    const filters: IncidentFilters = {};

    if (page) filters.page = parseInt(page, 10);
    if (limit) filters.limit = parseInt(limit, 10);
    if (status) filters.status = status;
    if (triggerType) filters.triggerType = triggerType;
    if (isTestMode !== undefined) filters.isTestMode = isTestMode === 'true';
    if (from) filters.from = new Date(from);
    if (to) filters.to = new Date(to);

    return this.incidentsService.findAll(user.id, filters);
  }

  @Get(':id')
  @ApiOperation({ summary: 'Get a single incident by ID' })
  @ApiResponse({ status: 200, description: 'Incident details' })
  @ApiResponse({ status: 404, description: 'Incident not found' })
  async findOne(
    @CurrentUser() user: CurrentUserPayload,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.incidentsService.findOne(id, user.id);
  }

  @Post(':id/activate')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Activate incident after countdown expires' })
  @ApiResponse({ status: 200, description: 'Incident activated' })
  async activate(
    @CurrentUser() user: CurrentUserPayload,
    @Param('id', ParseUUIDPipe) id: string,
  ) {
    return this.incidentsService.activate(id, user.id);
  }

  @Post(':id/events')
  @ApiOperation({ summary: 'Add an event to the incident timeline' })
  @ApiResponse({ status: 201, description: 'Event created' })
  async addEvent(
    @CurrentUser() user: CurrentUserPayload,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AddEventDto,
  ) {
    return this.incidentsService.addEvent(id, user.id, dto);
  }

  @Post(':id/resolve')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Resolve an active incident' })
  @ApiResponse({ status: 200, description: 'Incident resolved' })
  async resolve(
    @CurrentUser() user: CurrentUserPayload,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: ResolveIncidentDto,
  ) {
    return this.incidentsService.resolve(id, user.id, dto);
  }

  @Post(':id/cancel')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({
    summary: 'Cancel an incident (supports secret cancel for coercion scenario)',
  })
  @ApiResponse({ status: 200, description: 'Incident cancelled (or secretly escalated)' })
  async cancel(
    @CurrentUser() user: CurrentUserPayload,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CancelIncidentDto,
  ) {
    return this.incidentsService.cancel(id, user.id, dto);
  }

  @Post(':id/signal')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Send a risk signal for processing by the risk engine' })
  @ApiResponse({ status: 200, description: 'Signal processed, risk score updated' })
  async processSignal(
    @CurrentUser() user: CurrentUserPayload,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() body: { type: string; payload?: Record<string, any> },
  ) {
    return this.incidentsService.processRiskSignal(id, user.id, {
      type: body.type,
      payload: body.payload ?? {},
    });
  }
}
