import { Module } from '@nestjs/common';
import { HealthController } from './health.controller';
import { HealthService } from './health.service';
import { AdminGuard } from '../admin/guards/admin.guard';

@Module({
  controllers: [HealthController],
  providers: [HealthService, AdminGuard],
  exports: [HealthService],
})
export class HealthModule {}
