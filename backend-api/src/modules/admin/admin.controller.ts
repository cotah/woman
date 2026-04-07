import {
  Controller,
  Get,
  Patch,
  Param,
  Query,
  Body,
  UseGuards,
  ParseUUIDPipe,
  HttpCode,
  HttpStatus,
} from '@nestjs/common';
import { ApiTags, ApiBearerAuth, ApiOperation, ApiQuery } from '@nestjs/swagger';
import { AdminGuard } from './guards/admin.guard';
import { AdminService, IncidentListParams } from './admin.service';
import { CurrentUser } from '@/common/decorators/current-user.decorator';
import { AuthenticatedUser } from '@/common/interfaces/request-context';
import { AuditService } from '@/modules/audit/audit.service';
import { IncidentStatus, RiskLevel } from '@/modules/incidents/entities/incident.entity';

@ApiTags('Admin')
@ApiBearerAuth()
@UseGuards(AdminGuard)
@Controller('admin')
export class AdminController {
  constructor(
    private readonly adminService: AdminService,
    private readonly auditService: AuditService,
  ) {}

  // ── Incidents ──────────────────────────────

  @Get('incidents')
  @ApiOperation({ summary: 'List all incidents with filters' })
  @ApiQuery({ name: 'status', enum: IncidentStatus, required: false })
  @ApiQuery({ name: 'risk_level', enum: RiskLevel, required: false })
  @ApiQuery({ name: 'is_test_mode', type: Boolean, required: false })
  @ApiQuery({ name: 'start_date', type: String, required: false })
  @ApiQuery({ name: 'end_date', type: String, required: false })
  @ApiQuery({ name: 'user_id', type: String, required: false })
  @ApiQuery({ name: 'page', type: Number, required: false })
  @ApiQuery({ name: 'limit', type: Number, required: false })
  async listIncidents(
    @Query('status') status?: IncidentStatus,
    @Query('risk_level') riskLevel?: RiskLevel,
    @Query('is_test_mode') isTestMode?: string,
    @Query('start_date') startDate?: string,
    @Query('end_date') endDate?: string,
    @Query('user_id') userId?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    const params: IncidentListParams = {
      status,
      riskLevel,
      isTestMode: isTestMode !== undefined ? isTestMode === 'true' : undefined,
      startDate: startDate ? new Date(startDate) : undefined,
      endDate: endDate ? new Date(endDate) : undefined,
      userId,
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
    };
    return this.adminService.listIncidents(params);
  }

  @Get('incidents/:id')
  @ApiOperation({ summary: 'Get full incident detail' })
  async getIncident(@Param('id', ParseUUIDPipe) id: string) {
    return this.adminService.getIncidentDetail(id);
  }

  @Get('incidents/:id/timeline')
  @ApiOperation({ summary: 'Get full incident timeline' })
  @ApiQuery({ name: 'page', type: Number, required: false })
  @ApiQuery({ name: 'limit', type: Number, required: false })
  async getIncidentTimeline(
    @Param('id', ParseUUIDPipe) id: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.adminService.getIncidentTimeline(
      id,
      page ? parseInt(page, 10) : 1,
      limit ? parseInt(limit, 10) : 100,
    );
  }

  @Get('incidents/:id/audio')
  @ApiOperation({ summary: 'Get incident audio assets and transcripts' })
  async getIncidentAudio(@Param('id', ParseUUIDPipe) id: string) {
    return this.adminService.getIncidentAudio(id);
  }

  // ── Audit Logs ─────────────────────────────

  @Get('audit-logs')
  @ApiOperation({ summary: 'Search audit logs' })
  @ApiQuery({ name: 'user_id', required: false })
  @ApiQuery({ name: 'action', required: false })
  @ApiQuery({ name: 'resource', required: false })
  @ApiQuery({ name: 'resource_id', required: false })
  @ApiQuery({ name: 'start_date', required: false })
  @ApiQuery({ name: 'end_date', required: false })
  @ApiQuery({ name: 'page', type: Number, required: false })
  @ApiQuery({ name: 'limit', type: Number, required: false })
  async searchAuditLogs(
    @Query('user_id') userId?: string,
    @Query('action') action?: string,
    @Query('resource') resource?: string,
    @Query('resource_id') resourceId?: string,
    @Query('start_date') startDate?: string,
    @Query('end_date') endDate?: string,
    @Query('page') page?: string,
    @Query('limit') limit?: string,
  ) {
    return this.adminService.searchAuditLogs({
      userId,
      action,
      resource,
      resourceId,
      startDate: startDate ? new Date(startDate) : undefined,
      endDate: endDate ? new Date(endDate) : undefined,
      page: page ? parseInt(page, 10) : undefined,
      limit: limit ? parseInt(limit, 10) : undefined,
    });
  }

  // ── Feature Flags ──────────────────────────

  @Get('feature-flags')
  @ApiOperation({ summary: 'List all feature flags' })
  async listFeatureFlags() {
    return this.adminService.listFeatureFlags();
  }

  @Patch('feature-flags/:id')
  @HttpCode(HttpStatus.OK)
  @ApiOperation({ summary: 'Toggle a feature flag' })
  async toggleFeatureFlag(
    @Param('id', ParseUUIDPipe) id: string,
    @Body('enabled') enabled: boolean,
    @CurrentUser() user: AuthenticatedUser,
  ) {
    const result = await this.adminService.toggleFeatureFlag(id, enabled);

    // Audit the toggle action
    await this.auditService.log({
      action: 'feature_flag.toggle',
      resource: 'feature_flag',
      resourceId: id,
      details: { enabled, flagKey: result.key },
      userId: user.id,
    });

    return result;
  }

  // ── Health ─────────────────────────────────

  @Get('health')
  @ApiOperation({ summary: 'System health summary' })
  async getSystemHealth() {
    return this.adminService.getSystemHealth();
  }

  // ── Dashboard Stats ────────────────────────

  @Get('stats')
  @ApiOperation({ summary: 'Dashboard stats (active incidents, total users, alerts today)' })
  async getDashboardStats() {
    return this.adminService.getDashboardStats();
  }
}
