import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, SelectQueryBuilder, In } from 'typeorm';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';
import {
  Incident,
  IncidentStatus,
  RiskLevel,
} from '@/modules/incidents/entities/incident.entity';
import { IncidentEvent } from '@/modules/incidents/entities/incident-event.entity';
import { IncidentAudioAsset } from '@/modules/audio/entities/incident-audio-asset.entity';
import { IncidentTranscript } from '@/modules/audio/entities/incident-transcript.entity';
import { AlertDelivery } from '@/modules/notifications/entities/alert-delivery.entity';
import { User } from '@/modules/users/entities/user.entity';
import { AuditService, AuditLogSearchParams } from '@/modules/audit/audit.service';
import { FeatureFlagsService } from '@/modules/feature-flags/feature-flags.service';
import { HealthService } from '@/modules/health/health.service';

// ──────────────────────────────────────────────
// DTOs (kept co-located for admin-only queries)
// ──────────────────────────────────────────────

export interface IncidentListParams {
  status?: IncidentStatus;
  riskLevel?: RiskLevel;
  isTestMode?: boolean;
  startDate?: Date;
  endDate?: Date;
  userId?: string;
  page?: number;
  limit?: number;
}

export interface PaginatedResult<T> {
  data: T[];
  total: number;
  page: number;
  limit: number;
  totalPages: number;
}

export interface DashboardStats {
  activeIncidents: number;
  totalUsers: number;
  alertsSentToday: number;
  incidentsByStatus: Record<string, number>;
  incidentsByRiskLevel: Record<string, number>;
}

// ──────────────────────────────────────────────

@Injectable()
export class AdminService {
  private readonly logger = new Logger(AdminService.name);

  constructor(
    @InjectRepository(Incident)
    private readonly incidentRepo: Repository<Incident>,
    @InjectRepository(IncidentEvent)
    private readonly eventRepo: Repository<IncidentEvent>,
    @InjectRepository(IncidentAudioAsset)
    private readonly audioRepo: Repository<IncidentAudioAsset>,
    @InjectRepository(IncidentTranscript)
    private readonly transcriptRepo: Repository<IncidentTranscript>,
    @InjectRepository(AlertDelivery)
    private readonly alertRepo: Repository<AlertDelivery>,
    @InjectRepository(User)
    private readonly userRepo: Repository<User>,
    @InjectDataSource()
    private readonly dataSource: DataSource,
    private readonly auditService: AuditService,
    private readonly featureFlagsService: FeatureFlagsService,
    private readonly healthService: HealthService,
  ) {}

  // ── Incidents ──────────────────────────────

  async listIncidents(
    params: IncidentListParams,
  ): Promise<PaginatedResult<Incident>> {
    const page = Math.max(params.page ?? 1, 1);
    const limit = Math.min(Math.max(params.limit ?? 25, 1), 100);

    const qb: SelectQueryBuilder<Incident> = this.incidentRepo
      .createQueryBuilder('i')
      .orderBy('i.created_at', 'DESC');

    if (params.status) {
      qb.andWhere('i.status = :status', { status: params.status });
    }
    if (params.riskLevel) {
      qb.andWhere('i.current_risk_level = :riskLevel', {
        riskLevel: params.riskLevel,
      });
    }
    if (params.isTestMode !== undefined) {
      qb.andWhere('i.is_test_mode = :isTestMode', {
        isTestMode: params.isTestMode,
      });
    }
    if (params.startDate) {
      qb.andWhere('i.created_at >= :startDate', {
        startDate: params.startDate,
      });
    }
    if (params.endDate) {
      qb.andWhere('i.created_at <= :endDate', { endDate: params.endDate });
    }
    if (params.userId) {
      qb.andWhere('i.user_id = :userId', { userId: params.userId });
    }

    qb.skip((page - 1) * limit).take(limit);

    const [data, total] = await qb.getManyAndCount();
    return {
      data,
      total,
      page,
      limit,
      totalPages: Math.ceil(total / limit),
    };
  }

  async getIncidentDetail(id: string): Promise<Incident> {
    const incident = await this.incidentRepo.findOne({
      where: { id },
      relations: ['events', 'locations'],
    });
    if (!incident) {
      throw new NotFoundException(`Incident ${id} not found`);
    }
    return incident;
  }

  async getIncidentTimeline(
    incidentId: string,
    page = 1,
    limit = 100,
  ): Promise<PaginatedResult<IncidentEvent>> {
    // Verify incident exists
    const exists = await this.incidentRepo.count({ where: { id: incidentId } });
    if (!exists) {
      throw new NotFoundException(`Incident ${incidentId} not found`);
    }

    const safePage = Math.max(page, 1);
    const safeLimit = Math.min(Math.max(limit, 1), 500);

    const [data, total] = await this.eventRepo.findAndCount({
      where: { incidentId },
      order: { timestamp: 'ASC' },
      skip: (safePage - 1) * safeLimit,
      take: safeLimit,
    });

    return {
      data,
      total,
      page: safePage,
      limit: safeLimit,
      totalPages: Math.ceil(total / safeLimit),
    };
  }

  async getIncidentAudio(incidentId: string): Promise<{
    assets: IncidentAudioAsset[];
    transcripts: IncidentTranscript[];
  }> {
    const exists = await this.incidentRepo.count({ where: { id: incidentId } });
    if (!exists) {
      throw new NotFoundException(`Incident ${incidentId} not found`);
    }

    const [assets, transcripts] = await Promise.all([
      this.audioRepo.find({
        where: { incidentId },
        order: { chunkIndex: 'ASC' },
      }),
      this.transcriptRepo.find({
        where: { incidentId },
        order: { createdAt: 'ASC' },
      }),
    ]);

    return { assets, transcripts };
  }

  // ── Audit Logs ─────────────────────────────

  async searchAuditLogs(params: AuditLogSearchParams) {
    return this.auditService.search(params);
  }

  // ── Feature Flags ──────────────────────────

  async listFeatureFlags() {
    return this.featureFlagsService.findAll();
  }

  async toggleFeatureFlag(id: string, enabled: boolean) {
    return this.featureFlagsService.toggle(id, enabled);
  }

  // ── Health ─────────────────────────────────

  async getSystemHealth() {
    return this.healthService.getDetailedHealth();
  }

  // ── Dashboard Stats ────────────────────────

  async getDashboardStats(): Promise<DashboardStats> {
    const activeStatuses: IncidentStatus[] = [
      IncidentStatus.PENDING,
      IncidentStatus.COUNTDOWN,
      IncidentStatus.ACTIVE,
      IncidentStatus.ESCALATED,
    ];

    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);

    const [
      activeIncidents,
      totalUsers,
      alertsSentToday,
      statusCounts,
      riskCounts,
    ] = await Promise.all([
      this.incidentRepo.count({
        where: { status: In(activeStatuses) },
      }),
      this.userRepo.count(),
      this.alertRepo
        .createQueryBuilder('a')
        .where('a.created_at >= :todayStart', { todayStart })
        .getCount(),
      this.incidentRepo
        .createQueryBuilder('i')
        .select('i.status', 'status')
        .addSelect('COUNT(*)', 'count')
        .groupBy('i.status')
        .getRawMany<{ status: string; count: string }>(),
      this.incidentRepo
        .createQueryBuilder('i')
        .select('i.current_risk_level', 'level')
        .addSelect('COUNT(*)', 'count')
        .where('i.status IN (:...statuses)', { statuses: activeStatuses })
        .groupBy('i.current_risk_level')
        .getRawMany<{ level: string; count: string }>(),
    ]);

    const incidentsByStatus: Record<string, number> = {};
    for (const row of statusCounts) {
      incidentsByStatus[row.status] = parseInt(row.count, 10);
    }

    const incidentsByRiskLevel: Record<string, number> = {};
    for (const row of riskCounts) {
      incidentsByRiskLevel[row.level] = parseInt(row.count, 10);
    }

    return {
      activeIncidents,
      totalUsers,
      alertsSentToday,
      incidentsByStatus,
      incidentsByRiskLevel,
    };
  }
}
