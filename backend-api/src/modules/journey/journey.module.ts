import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { BullModule } from '@nestjs/bullmq';
import { Journey } from './entities/journey.entity';
import { JourneyService } from './journey.service';
import { JourneyController } from './journey.controller';
import { JourneyExpiryProcessor } from '../../queue/journey-expiry.processor';
import { IncidentsModule } from '../incidents/incidents.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([Journey]),
    BullModule.registerQueue({ name: 'journey-expiry' }),
    IncidentsModule,
  ],
  controllers: [JourneyController],
  providers: [JourneyService, JourneyExpiryProcessor],
  exports: [JourneyService],
})
export class JourneyModule {}
