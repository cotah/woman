import { Controller, Get, SetMetadata, UseGuards } from '@nestjs/common';
import { ApiTags, ApiOperation, ApiBearerAuth } from '@nestjs/swagger';
import { ConfigService } from '@nestjs/config';
import { IS_PUBLIC_KEY } from '../auth/guards/jwt-auth.guard';
import { AdminGuard } from '../admin/guards/admin.guard';
import { HealthService, HealthReport } from './health.service';

const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

@ApiTags('Health')
@Controller('health')
export class HealthController {
  constructor(
    private readonly healthService: HealthService,
    private readonly configService: ConfigService,
  ) {}

  @Get()
  @Public()
  @ApiOperation({ summary: 'Basic liveness check' })
  getHealth(): HealthReport {
    return this.healthService.getBasicHealth();
  }

  @Get('detailed')
  @ApiOperation({ summary: 'Detailed readiness check (DB, Redis, S3)' })
  async getDetailedHealth(): Promise<HealthReport> {
    return this.healthService.getDetailedHealth();
  }

  /**
   * GET /health/pilot
   * Pilot testing endpoint: reports which providers are configured vs dry-run.
   * Restricted to admin/super_admin — leaks which third-party services are
   * wired up (Twilio, Firebase, Deepgram, OpenAI), which is reconnaissance
   * material for an attacker if exposed publicly.
   */
  @Get('pilot')
  @UseGuards(AdminGuard)
  @ApiBearerAuth()
  @ApiOperation({ summary: 'Pilot readiness: provider configuration status' })
  getPilotReadiness() {
    const twilioSid = this.configService.get<string>('TWILIO_ACCOUNT_SID');
    const twilioToken = this.configService.get<string>('TWILIO_AUTH_TOKEN');
    const firebaseProject = this.configService.get<string>('FIREBASE_PROJECT_ID');
    const deepgramKey = this.configService.get<string>('DEEPGRAM_API_KEY');
    const openaiKey = this.configService.get<string>('OPENAI_API_KEY');

    return {
      environment: this.configService.get<string>('NODE_ENV', 'development'),
      providers: {
        twilio_sms: {
          configured: !!(twilioSid && twilioToken),
          mode: (twilioSid && twilioToken) ? 'LIVE' : 'DRY-RUN',
        },
        firebase_push: {
          configured: !!firebaseProject,
          mode: firebaseProject ? 'LIVE' : 'DRY-RUN',
        },
        deepgram_stt: {
          configured: !!deepgramKey,
          mode: deepgramKey ? 'LIVE' : 'DRY-RUN',
        },
        openai_analysis: {
          configured: !!openaiKey,
          mode: openaiKey ? 'LIVE' : 'DRY-RUN',
        },
      },
      timestamp: new Date().toISOString(),
    };
  }
}
