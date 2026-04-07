import { Injectable, Logger } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';
import { ConfigService } from '@nestjs/config';
import Redis from 'ioredis';
import {
  S3Client,
  HeadBucketCommand,
} from '@aws-sdk/client-s3';

export interface ComponentHealth {
  status: 'healthy' | 'degraded' | 'unhealthy';
  latencyMs?: number;
  message?: string;
}

export interface HealthReport {
  status: 'healthy' | 'degraded' | 'unhealthy';
  uptime: number;
  timestamp: string;
  version: string;
  components?: {
    database: ComponentHealth;
    redis: ComponentHealth;
    s3: ComponentHealth;
  };
}

@Injectable()
export class HealthService {
  private readonly logger = new Logger(HealthService.name);
  private readonly startTime = Date.now();

  constructor(
    @InjectDataSource()
    private readonly dataSource: DataSource,
    private readonly configService: ConfigService,
  ) {}

  /** Lightweight liveness probe */
  getBasicHealth(): HealthReport {
    return {
      status: 'healthy',
      uptime: Math.floor((Date.now() - this.startTime) / 1000),
      timestamp: new Date().toISOString(),
      version: process.env.npm_package_version || '1.0.0',
    };
  }

  /** Full readiness probe - checks DB, Redis, S3 */
  async getDetailedHealth(): Promise<HealthReport> {
    const [db, redis, s3] = await Promise.all([
      this.checkDatabase(),
      this.checkRedis(),
      this.checkS3(),
    ]);

    const components = { database: db, redis, s3 };

    const statuses = Object.values(components).map((c) => c.status);
    let overall: HealthReport['status'] = 'healthy';
    if (statuses.includes('unhealthy')) overall = 'unhealthy';
    else if (statuses.includes('degraded')) overall = 'degraded';

    return {
      status: overall,
      uptime: Math.floor((Date.now() - this.startTime) / 1000),
      timestamp: new Date().toISOString(),
      version: process.env.npm_package_version || '1.0.0',
      components,
    };
  }

  private async checkDatabase(): Promise<ComponentHealth> {
    const start = Date.now();
    try {
      await this.dataSource.query('SELECT 1');
      return {
        status: 'healthy',
        latencyMs: Date.now() - start,
      };
    } catch (error) {
      this.logger.error(`Database health check failed: ${error.message}`);
      return {
        status: 'unhealthy',
        latencyMs: Date.now() - start,
        message: error.message,
      };
    }
  }

  private async checkRedis(): Promise<ComponentHealth> {
    const start = Date.now();
    let client: Redis | null = null;
    try {
      const redisUrl =
        this.configService.get<string>('REDIS_URL') || 'redis://localhost:6379';
      client = new Redis(redisUrl, {
        connectTimeout: 3000,
        lazyConnect: true,
      });
      await client.connect();
      const pong = await client.ping();
      const latencyMs = Date.now() - start;
      return {
        status: pong === 'PONG' ? 'healthy' : 'degraded',
        latencyMs,
      };
    } catch (error) {
      this.logger.error(`Redis health check failed: ${error.message}`);
      return {
        status: 'unhealthy',
        latencyMs: Date.now() - start,
        message: error.message,
      };
    } finally {
      if (client) {
        try {
          await client.quit();
        } catch {
          // ignore cleanup errors
        }
      }
    }
  }

  private async checkS3(): Promise<ComponentHealth> {
    const start = Date.now();
    try {
      const region = this.configService.get<string>('AWS_REGION') || 'us-east-1';
      const bucket = this.configService.get<string>('S3_BUCKET');
      if (!bucket) {
        return {
          status: 'degraded',
          latencyMs: Date.now() - start,
          message: 'S3_BUCKET not configured',
        };
      }

      const s3 = new S3Client({ region });
      await s3.send(new HeadBucketCommand({ Bucket: bucket }));
      return {
        status: 'healthy',
        latencyMs: Date.now() - start,
      };
    } catch (error) {
      this.logger.error(`S3 health check failed: ${error.message}`);
      return {
        status: 'unhealthy',
        latencyMs: Date.now() - start,
        message: error.message,
      };
    }
  }
}
