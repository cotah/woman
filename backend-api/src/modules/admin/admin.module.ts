import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';
import { AdminGuard } from './guards/admin.guard';
import { Incident } from '@/modules/incidents/entities/incident.entity';
import { IncidentEvent } from '@/modules/incidents/entities/incident-event.entity';
import { IncidentAudioAsset } from '@/modules/audio/entities/incident-audio-asset.entity';
import { IncidentTranscript } from '@/modules/audio/entities/incident-transcript.entity';
import { AlertDelivery } from '@/modules/notifications/entities/alert-delivery.entity';
import { User } from '@/modules/users/entities/user.entity';
import { HealthModule } from '@/modules/health/health.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Incident,
      IncidentEvent,
      IncidentAudioAsset,
      IncidentTranscript,
      AlertDelivery,
      User,
    ]),
    HealthModule,
  ],
  controllers: [AdminController],
  providers: [AdminService, AdminGuard],
})
export class AdminModule {}
