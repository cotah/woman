import {
  Controller,
  Post,
  Get,
  Param,
  Body,
  ParseUUIDPipe,
  HttpCode,
  HttpStatus,
  Headers,
  UnauthorizedException,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiParam,
  ApiResponse,
  ApiHeader,
} from '@nestjs/swagger';
import { NotificationsService } from './notifications.service';
import { ContactRespondDto } from './dto/contact-respond.dto';
import { ContactAccessService } from '../contacts/contact-access.service';

@ApiTags('Notifications / Contact Response')
@Controller('incidents')
export class NotificationsController {
  constructor(
    private readonly notificationsService: NotificationsService,
    private readonly contactAccessService: ContactAccessService,
  ) {}

  /**
   * POST /incidents/:id/respond
   * Allows a trusted contact to respond to an incident.
   * Authenticated via contact access token (bearer or query).
   */
  @Post(':id/respond')
  @HttpCode(HttpStatus.CREATED)
  @ApiOperation({
    summary: 'Record a trusted contact response to an incident',
    description:
      'Used by trusted contacts through the secure web view to indicate their response action.',
  })
  @ApiParam({ name: 'id', description: 'Incident ID', type: 'string' })
  @ApiHeader({
    name: 'x-access-token',
    description: 'Contact access token for authentication',
    required: true,
  })
  @ApiResponse({ status: 201, description: 'Response recorded successfully' })
  @ApiResponse({ status: 401, description: 'Invalid or expired access token' })
  @ApiResponse({ status: 404, description: 'Incident not found' })
  async respondToIncident(
    @Param('id', ParseUUIDPipe) incidentId: string,
    @Headers('x-access-token') accessToken: string,
    @Body() dto: ContactRespondDto,
  ) {
    if (!accessToken) {
      throw new UnauthorizedException('Access token is required');
    }

    const tokenData = await this.contactAccessService.validateToken(accessToken);

    if (!tokenData || tokenData.incidentId !== incidentId) {
      throw new UnauthorizedException('Invalid or expired access token');
    }

    const response = await this.notificationsService.recordContactResponse(
      incidentId,
      tokenData.contactId,
      dto,
    );

    return {
      id: response.id,
      incidentId: response.incidentId,
      responseType: response.responseType,
      respondedAt: response.respondedAt,
    };
  }

  /**
   * GET /incidents/:id/deliveries
   * Get all alert deliveries for an incident (internal/admin use).
   */
  @Get(':id/deliveries')
  @ApiOperation({ summary: 'List alert deliveries for an incident' })
  @ApiParam({ name: 'id', type: 'string' })
  @ApiResponse({ status: 200, description: 'List of deliveries' })
  async getDeliveries(@Param('id', ParseUUIDPipe) incidentId: string) {
    return this.notificationsService.getDeliveriesByIncident(incidentId);
  }

  /**
   * GET /incidents/:id/responses
   * Get all contact responses for an incident.
   */
  @Get(':id/responses')
  @ApiOperation({ summary: 'List contact responses for an incident' })
  @ApiParam({ name: 'id', type: 'string' })
  @ApiResponse({ status: 200, description: 'List of responses' })
  async getResponses(@Param('id', ParseUUIDPipe) incidentId: string) {
    return this.notificationsService.getResponsesByIncident(incidentId);
  }
}
