import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { IncidentsController } from './incidents.controller';
import { IncidentsService } from './incidents.service';
import { Incident } from './entities/incident.entity';
import { IncidentEvent } from './entities/incident-event.entity';
import { IncidentLocation } from './entities/incident-location.entity';
import { RiskAssessment } from './entities/risk-assessment.entity';
import { RiskEngineModule } from '../risk-engine/risk-engine.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([
      Incident,
      IncidentEvent,
      IncidentLocation,
      RiskAssessment,
    ]),
    RiskEngineModule,
  ],
  controllers: [IncidentsController],
  providers: [IncidentsService],
  exports: [IncidentsService],
})
export class IncidentsModule {}
