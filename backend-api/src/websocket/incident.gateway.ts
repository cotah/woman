import {
  WebSocketGateway,
  WebSocketServer,
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
  SubscribeMessage,
  MessageBody,
  ConnectedSocket,
} from '@nestjs/websockets';
import { Logger, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { Server, Socket } from 'socket.io';
import { JwtPayload } from '@/common/interfaces/request-context';

export interface IncidentUpdatePayload {
  incidentId: string;
  [key: string]: unknown;
}

@WebSocketGateway({
  namespace: '/incidents',
  cors: {
    origin: process.env.CORS_ORIGINS?.split(',') || ['http://localhost:3000', 'http://localhost:5173'],
    credentials: true,
  },
  transports: ['websocket', 'polling'],
})
export class IncidentGateway
  implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect
{
  @WebSocketServer()
  server: Server;

  private readonly logger = new Logger(IncidentGateway.name);

  constructor(
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
  ) {}

  afterInit(): void {
    this.logger.log('Incident WebSocket gateway initialized');
  }

  /**
   * Authenticate on connection via JWT in query params or auth header.
   * If invalid, disconnect immediately.
   */
  async handleConnection(client: Socket): Promise<void> {
    try {
      const token = this.extractToken(client);
      if (!token) {
        throw new UnauthorizedException('No token provided');
      }

      const payload = this.jwtService.verify<JwtPayload>(token, {
        secret: this.configService.get<string>('app.jwt.secret'),
      });

      // Attach user data to socket for later use
      client.data.user = {
        id: payload.sub,
        email: payload.email,
        role: payload.role,
      };

      this.logger.log(
        `Client connected: ${client.id} (user: ${payload.sub})`,
      );
    } catch (error) {
      this.logger.warn(
        `Connection rejected for ${client.id}: ${error.message}`,
      );
      client.emit('error', { message: 'Authentication failed' });
      client.disconnect(true);
    }
  }

  handleDisconnect(client: Socket): void {
    this.logger.log(`Client disconnected: ${client.id}`);
  }

  // ── Client-initiated events ────────────────

  @SubscribeMessage('join:incident')
  handleJoinIncident(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { incidentId: string },
  ): void {
    const room = `incident:${data.incidentId}`;
    client.join(room);
    this.logger.debug(
      `Client ${client.id} joined room ${room}`,
    );
    client.emit('joined', { room, incidentId: data.incidentId });
  }

  @SubscribeMessage('leave:incident')
  handleLeaveIncident(
    @ConnectedSocket() client: Socket,
    @MessageBody() data: { incidentId: string },
  ): void {
    const room = `incident:${data.incidentId}`;
    client.leave(room);
    this.logger.debug(
      `Client ${client.id} left room ${room}`,
    );
  }

  // ── Server-side broadcast methods ──────────
  // These are called by services (not by clients) to push real-time updates.

  broadcastIncidentUpdate(incidentId: string, data: Record<string, unknown>): void {
    this.server
      .to(`incident:${incidentId}`)
      .emit('incident:update', { incidentId, ...data });
  }

  broadcastLocationUpdate(
    incidentId: string,
    location: { latitude: number; longitude: number; accuracy?: number; timestamp: string },
  ): void {
    this.server
      .to(`incident:${incidentId}`)
      .emit('location:update', { incidentId, location });
  }

  broadcastRiskUpdate(
    incidentId: string,
    risk: { previousScore: number; newScore: number; previousLevel: string; newLevel: string; reason: string },
  ): void {
    this.server
      .to(`incident:${incidentId}`)
      .emit('risk:update', { incidentId, risk });
  }

  broadcastAlertUpdate(
    incidentId: string,
    alert: { alertId: string; channel: string; status: string; contactId: string },
  ): void {
    this.server
      .to(`incident:${incidentId}`)
      .emit('alert:update', { incidentId, alert });
  }

  broadcastContactResponse(
    incidentId: string,
    response: { contactId: string; responseType: string; note?: string },
  ): void {
    this.server
      .to(`incident:${incidentId}`)
      .emit('contact:response', { incidentId, response });
  }

  broadcastTimelineEvent(
    incidentId: string,
    event: { type: string; payload: Record<string, unknown>; timestamp: string },
  ): void {
    this.server
      .to(`incident:${incidentId}`)
      .emit('timeline:event', { incidentId, event });
  }

  // ── Helpers ────────────────────────────────

  private extractToken(client: Socket): string | null {
    // Try query parameter first (used by mobile clients)
    const queryToken = client.handshake.query?.token as string;
    if (queryToken) {
      return queryToken;
    }

    // Try Authorization header
    const authHeader = client.handshake.headers?.authorization;
    if (authHeader?.startsWith('Bearer ')) {
      return authHeader.slice(7);
    }

    // Try auth object (socket.io v4+)
    const authToken = (client.handshake.auth as { token?: string })?.token;
    if (authToken) {
      return authToken;
    }

    return null;
  }
}
