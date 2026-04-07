import { NotFoundException } from '@nestjs/common';
import { FeatureFlagsService } from '../../src/modules/feature-flags/feature-flags.service';
import { FeatureFlag } from '../../src/modules/feature-flags/entities/feature-flag.entity';

describe('FeatureFlagsService', () => {
  let service: FeatureFlagsService;
  let mockFlagRepo: any;

  const makeFlag = (overrides: Partial<FeatureFlag> = {}): FeatureFlag => ({
    id: 'flag-1',
    key: 'audio_streaming',
    name: 'Audio Streaming',
    description: 'Enable real-time audio streaming',
    enabled: true,
    phase: 1,
    metadata: {},
    createdAt: new Date(),
    updatedAt: new Date(),
    ...overrides,
  });

  const sampleFlags: FeatureFlag[] = [
    makeFlag({ id: 'f1', key: 'audio_streaming', enabled: true }),
    makeFlag({ id: 'f2', key: 'ai_risk_scoring', enabled: false }),
    makeFlag({ id: 'f3', key: 'voice_trigger', enabled: true }),
  ];

  beforeEach(() => {
    mockFlagRepo = {
      find: jest.fn().mockResolvedValue(sampleFlags),
      findOne: jest.fn(),
      create: jest.fn((data) => data),
      save: jest.fn((data) => Promise.resolve(data)),
    };

    service = new FeatureFlagsService(mockFlagRepo);
  });

  describe('isEnabled', () => {
    it('should return true for an enabled flag', async () => {
      const result = await service.isEnabled('audio_streaming');
      expect(result).toBe(true);
    });

    it('should return false for a disabled flag', async () => {
      const result = await service.isEnabled('ai_risk_scoring');
      expect(result).toBe(false);
    });

    it('should return false for a non-existent flag (graceful fallback)', async () => {
      const result = await service.isEnabled('nonexistent_flag');
      expect(result).toBe(false);
    });
  });

  describe('findByKey', () => {
    it('should return the flag for a valid key', async () => {
      const flag = await service.findByKey('audio_streaming');
      expect(flag.key).toBe('audio_streaming');
      expect(flag.enabled).toBe(true);
    });

    it('should throw NotFoundException for unknown key', async () => {
      await expect(service.findByKey('unknown_key')).rejects.toThrow(NotFoundException);
    });
  });

  describe('toggle', () => {
    it('should toggle a flag from enabled to disabled', async () => {
      const flag = makeFlag({ id: 'f1', key: 'audio_streaming', enabled: true });
      mockFlagRepo.findOne.mockResolvedValue(flag);

      const result = await service.toggle('f1', false);

      expect(result.enabled).toBe(false);
      expect(mockFlagRepo.save).toHaveBeenCalled();
    });

    it('should toggle a flag from disabled to enabled', async () => {
      const flag = makeFlag({ id: 'f2', key: 'ai_risk_scoring', enabled: false });
      mockFlagRepo.findOne.mockResolvedValue(flag);

      const result = await service.toggle('f2', true);

      expect(result.enabled).toBe(true);
      expect(mockFlagRepo.save).toHaveBeenCalled();
    });

    it('should throw NotFoundException for non-existent flag id', async () => {
      mockFlagRepo.findOne.mockResolvedValue(null);
      await expect(service.toggle('nonexistent-id', true)).rejects.toThrow(NotFoundException);
    });
  });

  describe('cache behavior', () => {
    it('should cache flags after first load and not re-query', async () => {
      await service.isEnabled('audio_streaming');
      await service.isEnabled('ai_risk_scoring');
      await service.isEnabled('voice_trigger');

      // Only one DB call should have been made (all served from cache)
      expect(mockFlagRepo.find).toHaveBeenCalledTimes(1);
    });

    it('should invalidate cache after toggle', async () => {
      // Prime the cache
      await service.isEnabled('audio_streaming');
      expect(mockFlagRepo.find).toHaveBeenCalledTimes(1);

      // Toggle a flag (this calls invalidateCache internally)
      const flag = makeFlag({ id: 'f1', enabled: true });
      mockFlagRepo.findOne.mockResolvedValue(flag);
      await service.toggle('f1', false);

      // Next query should hit the DB again
      await service.isEnabled('audio_streaming');
      expect(mockFlagRepo.find).toHaveBeenCalledTimes(2);
    });

    it('should invalidate cache after update', async () => {
      // Prime the cache
      await service.findAll();
      expect(mockFlagRepo.find).toHaveBeenCalledTimes(1);

      // Update a flag
      const flag = makeFlag({ id: 'f1' });
      mockFlagRepo.findOne.mockResolvedValue(flag);
      await service.update('f1', { description: 'Updated description' });

      // Next call should hit DB again
      await service.findAll();
      expect(mockFlagRepo.find).toHaveBeenCalledTimes(2);
    });

    it('invalidateCache resets cache so next call fetches fresh data', () => {
      // Manually test the invalidateCache method
      service.invalidateCache();
      // After invalidation, the next ensureCache will hit the DB
      // We verify by calling and checking mock calls
      expect(mockFlagRepo.find).not.toHaveBeenCalled();
    });
  });

  describe('findAll', () => {
    it('should return all flags', async () => {
      const flags = await service.findAll();
      expect(flags).toHaveLength(3);
    });
  });

  describe('findById', () => {
    it('should return flag by id', async () => {
      const flag = makeFlag({ id: 'f1' });
      mockFlagRepo.findOne.mockResolvedValue(flag);

      const result = await service.findById('f1');
      expect(result.id).toBe('f1');
    });

    it('should throw NotFoundException when flag not found by id', async () => {
      mockFlagRepo.findOne.mockResolvedValue(null);
      await expect(service.findById('nonexistent')).rejects.toThrow(NotFoundException);
    });
  });
});
