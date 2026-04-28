import { Module } from '@nestjs/common';
import { AuthModule } from '../modules/auth/auth.module';
import { IncidentGateway } from './incident.gateway';

/**
 * WebsocketModule — provides real-time WebSocket
 * communication via IncidentGateway.
 *
 * The gateway broadcasts events like incident:update,
 * timeline:event, contact:response to the mobile app
 * during emergencies. Without this module registering
 * the gateway as a provider, the gateway is inert
 * (instantiated by NestJS but never bound to the
 * WebSocket transport).
 *
 * Discovered as adjacent bug during pipeline-fix Fix 2
 * — same pattern as AudioProcessor not being registered.
 */
@Module({
  imports: [AuthModule], // for JwtService (used in gateway auth handshake)
  providers: [IncidentGateway],
  exports: [IncidentGateway],
})
export class WebsocketModule {}
