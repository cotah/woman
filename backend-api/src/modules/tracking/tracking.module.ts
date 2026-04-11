import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { TrackingController } from './tracking.controller';
import { TrackingService } from './tracking.service';
import { LocationSnapshot, LearnedPlace } from './tracking.entity';

@Module({
  imports: [TypeOrmModule.forFeature([LocationSnapshot, LearnedPlace])],
  controllers: [TrackingController],
  providers: [TrackingService],
  exports: [TrackingService],
})
export class TrackingModule {}
