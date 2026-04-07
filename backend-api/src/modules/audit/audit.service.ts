import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, SelectQueryBuilder } from 'typeorm';
import { AuditLog } from './entities/audit-log.entity';

export interface AuditLogParams {
  action: string;
  resource: string;
  resourceId?: string;
  details?: Record<string, any>;
  userId?: string;
  ip?: string;
  userAgent?: string;
}

export interface AuditLogSearchParams {
  userId?: string;
  action?: string;
  resource?: string;
  resourceId?: string;
  startDate?: Date;
  endDate?: Date;
  page?: number;
  limit?: number;
}

@Injectable()
export class AuditService {
  private readonly logger = new Logger(AuditService.name);

  constructor(
    @InjectRepository(AuditLog)
    private readonly auditLogRepository: Repository<AuditLog>,
  ) {}

  /**
   * Append-only audit log entry. Fire-and-forget by default to avoid
   * slowing down the calling request. If the caller needs confirmation,
   * they can await the returned promise.
   */
  async log(params: AuditLogParams): Promise<AuditLog | null> {
    try {
      const entry = this.auditLogRepository.create({
        action: params.action,
        resource: params.resource,
        resourceId: params.resourceId ?? null,
        details: params.details ?? {},
        userId: params.userId ?? null,
        ipAddress: params.ip ?? null,
        userAgent: params.userAgent ?? null,
      });
      return await this.auditLogRepository.save(entry);
    } catch (error) {
      // Audit logging must never crash the caller
      this.logger.error(
        `Failed to write audit log: ${error.message}`,
        error.stack,
      );
      return null;
    }
  }

  async search(
    params: AuditLogSearchParams,
  ): Promise<{ data: AuditLog[]; total: number; page: number; limit: number }> {
    const page = Math.max(params.page ?? 1, 1);
    const limit = Math.min(Math.max(params.limit ?? 50, 1), 200);

    const qb: SelectQueryBuilder<AuditLog> = this.auditLogRepository
      .createQueryBuilder('log')
      .orderBy('log.timestamp', 'DESC');

    if (params.userId) {
      qb.andWhere('log.user_id = :userId', { userId: params.userId });
    }
    if (params.action) {
      qb.andWhere('log.action = :action', { action: params.action });
    }
    if (params.resource) {
      qb.andWhere('log.resource = :resource', { resource: params.resource });
    }
    if (params.resourceId) {
      qb.andWhere('log.resource_id = :resourceId', {
        resourceId: params.resourceId,
      });
    }
    if (params.startDate) {
      qb.andWhere('log.timestamp >= :startDate', {
        startDate: params.startDate,
      });
    }
    if (params.endDate) {
      qb.andWhere('log.timestamp <= :endDate', { endDate: params.endDate });
    }

    qb.skip((page - 1) * limit).take(limit);

    const [data, total] = await qb.getManyAndCount();
    return { data, total, page, limit };
  }
}
