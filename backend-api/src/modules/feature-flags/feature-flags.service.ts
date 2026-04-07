import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { FeatureFlag } from './entities/feature-flag.entity';

const CACHE_TTL_MS = 60_000; // 1 minute

@Injectable()
export class FeatureFlagsService {
  private readonly logger = new Logger(FeatureFlagsService.name);
  private cache: Map<string, FeatureFlag> | null = null;
  private cacheExpiresAt = 0;

  constructor(
    @InjectRepository(FeatureFlag)
    private readonly flagRepository: Repository<FeatureFlag>,
  ) {}

  /** Refresh in-memory cache if stale */
  private async ensureCache(): Promise<Map<string, FeatureFlag>> {
    if (this.cache && Date.now() < this.cacheExpiresAt) {
      return this.cache;
    }

    const flags = await this.flagRepository.find();
    this.cache = new Map(flags.map((f) => [f.key, f]));
    this.cacheExpiresAt = Date.now() + CACHE_TTL_MS;
    return this.cache;
  }

  /** Invalidate the in-memory cache (e.g. after a toggle) */
  invalidateCache(): void {
    this.cache = null;
    this.cacheExpiresAt = 0;
  }

  async findAll(): Promise<FeatureFlag[]> {
    const cache = await this.ensureCache();
    return Array.from(cache.values());
  }

  async findByKey(key: string): Promise<FeatureFlag> {
    const cache = await this.ensureCache();
    const flag = cache.get(key);
    if (!flag) {
      throw new NotFoundException(`Feature flag "${key}" not found`);
    }
    return flag;
  }

  async findById(id: string): Promise<FeatureFlag> {
    const flag = await this.flagRepository.findOne({ where: { id } });
    if (!flag) {
      throw new NotFoundException(`Feature flag with id "${id}" not found`);
    }
    return flag;
  }

  async isEnabled(key: string): Promise<boolean> {
    try {
      const flag = await this.findByKey(key);
      return flag.enabled;
    } catch {
      this.logger.warn(
        `Feature flag "${key}" not found, defaulting to disabled`,
      );
      return false;
    }
  }

  async toggle(id: string, enabled: boolean): Promise<FeatureFlag> {
    const flag = await this.findById(id);
    flag.enabled = enabled;
    const saved = await this.flagRepository.save(flag);
    this.invalidateCache();
    return saved;
  }

  async update(
    id: string,
    updates: Partial<Pick<FeatureFlag, 'enabled' | 'metadata' | 'description'>>,
  ): Promise<FeatureFlag> {
    const flag = await this.findById(id);
    Object.assign(flag, updates);
    const saved = await this.flagRepository.save(flag);
    this.invalidateCache();
    return saved;
  }
}
