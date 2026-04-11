import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { BullModule } from '@nestjs/bullmq';
import { ThrottlerModule, ThrottlerGuard } from '@nestjs/throttler';
import { SentryModule } from '@sentry/nestjs/setup';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { SentryGlobalFilter } from '@sentry/nestjs/setup';
import appConfig from './config/app.config';
import databaseConfig from './config/database.config';
import { AuthModule } from './modules/auth/auth.module';
import { UsersModule } from './modules/users/users.module';
import { IncidentsModule } from './modules/incidents/incidents.module';
import { ContactsModule } from './modules/contacts/contacts.module';
import { SettingsModule } from './modules/settings/settings.module';
import { LocationModule } from './modules/location/location.module';
import { AudioModule } from './modules/audio/audio.module';
import { NotificationsModule } from './modules/notifications/notifications.module';
import { RiskEngineModule } from './modules/risk-engine/risk-engine.module';
import { TimelineModule } from './modules/timeline/timeline.module';
import { AuditModule } from './modules/audit/audit.module';
import { FeatureFlagsModule } from './modules/feature-flags/feature-flags.module';
import { HealthModule } from './modules/health/health.module';
import { AdminModule } from './modules/admin/admin.module';
import { JourneyModule } from './modules/journey/journey.module';
import { TrackingModule } from './modules/tracking/tracking.module';
import { JwtAuthGuard } from './modules/auth/guards/jwt-auth.guard';
import { RolesGuard } from './modules/auth/guards/roles.guard';
import { GlobalExceptionFilter } from './common/filters/http-exception.filter';
import { AuditInterceptor } from './common/interceptors/audit.interceptor';

@Module({
  imports: [
    // Sentry error monitoring (must be first)
    SentryModule.forRoot(),

    // Configuration
    ConfigModule.forRoot({
      isGlobal: true,
      load: [appConfig, databaseConfig],
      envFilePath: ['.env.local', '.env'],
    }),

    // Database
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => ({
        type: 'postgres' as const,
        host: configService.get<string>('database.host'),
        port: configService.get<number>('database.port'),
        username: configService.get<string>('database.username'),
        password: configService.get<string>('database.password'),
        database: configService.get<string>('database.database'),
        ssl: configService.get<boolean>('database.ssl') || false,
        autoLoadEntities: true,
        synchronize: false,
        logging: configService.get<boolean>('database.logging'),
        migrationsRun: configService.get<boolean>('database.migrationsRun'),
      }),
    }),

    // Queue (BullMQ + Redis)
    BullModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => ({
        connection: {
          host: configService.get<string>('app.redis.host', 'localhost'),
          port: configService.get<number>('app.redis.port', 6379),
          password: configService.get<string>('app.redis.password'),
        },
      }),
    }),

    // Rate limiting
    ThrottlerModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => ({
        throttlers: [
          {
            name: 'default',
            ttl: configService.get<number>('app.throttle.ttl', 60) * 1000,
            limit: configService.get<number>('app.throttle.limit', 60),
          },
        ],
      }),
    }),

    // Feature modules
    AuthModule,
    UsersModule,
    IncidentsModule,
    ContactsModule,
    SettingsModule,
    LocationModule,
    AudioModule,
    NotificationsModule,
    RiskEngineModule,
    TimelineModule,
    AuditModule,
    FeatureFlagsModule,
    HealthModule,
    AdminModule,
    JourneyModule,
    TrackingModule,
  ],
  providers: [
    // Sentry global filter (catches all unhandled exceptions)
    {
      provide: APP_FILTER,
      useClass: SentryGlobalFilter,
    },
    // Global exception filter
    {
      provide: APP_FILTER,
      useClass: GlobalExceptionFilter,
    },
    // Global JWT guard (all routes require auth unless marked @Public())
    {
      provide: APP_GUARD,
      useClass: JwtAuthGuard,
    },
    // Global role guard
    {
      provide: APP_GUARD,
      useClass: RolesGuard,
    },
    // Global rate limiting guard (60 requests per minute per IP)
    {
      provide: APP_GUARD,
      useClass: ThrottlerGuard,
    },
    // Global audit interceptor
    {
      provide: APP_INTERCEPTOR,
      useClass: AuditInterceptor,
    },
  ],
})
export class AppModule {}
