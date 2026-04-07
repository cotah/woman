import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { RiskEngineService } from './risk-engine.service';
import { RiskAssessment } from '../incidents/entities/risk-assessment.entity';
import { RISK_SCORING_STRATEGY } from './interfaces/risk-scoring-strategy';

@Module({
  imports: [TypeOrmModule.forFeature([RiskAssessment])],
  providers: [
    RiskEngineService,
    {
      provide: RISK_SCORING_STRATEGY,
      useExisting: RiskEngineService,
    },
  ],
  exports: [RiskEngineService, RISK_SCORING_STRATEGY],
})
export class RiskEngineModule {}
