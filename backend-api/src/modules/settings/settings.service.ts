import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { EmergencySettings } from './entities/emergency-settings.entity';
import { UpdateEmergencySettingsDto } from './dto/update-emergency-settings.dto';

const BCRYPT_ROUNDS = 12;

@Injectable()
export class SettingsService {
  private readonly logger = new Logger(SettingsService.name);

  constructor(
    @InjectRepository(EmergencySettings)
    private readonly settingsRepository: Repository<EmergencySettings>,
  ) {}

  /**
   * Returns the user's emergency settings, auto-creating defaults on first access.
   */
  async getEmergencySettings(userId: string): Promise<EmergencySettings> {
    let settings = await this.settingsRepository.findOne({
      where: { userId },
    });

    if (!settings) {
      settings = this.settingsRepository.create({ userId });
      settings = await this.settingsRepository.save(settings);
      this.logger.log(`Default emergency settings created for user ${userId}`);
    }

    return settings;
  }

  /**
   * Updates emergency settings for the given user.
   * Auto-creates defaults first if they don't exist.
   */
  async updateEmergencySettings(
    userId: string,
    dto: UpdateEmergencySettingsDto,
  ): Promise<EmergencySettings> {
    let settings = await this.getEmergencySettings(userId);

    Object.assign(settings, dto);
    settings = await this.settingsRepository.save(settings);

    this.logger.log(`Emergency settings updated for user ${userId}`);
    return settings;
  }

  /**
   * Hashes and stores a coercion PIN.
   * The plain PIN is never persisted or returned.
   */
  async setCoercionPin(userId: string, pin: string): Promise<void> {
    const settings = await this.getEmergencySettings(userId);

    const hash = await bcrypt.hash(pin, BCRYPT_ROUNDS);

    await this.settingsRepository
      .createQueryBuilder()
      .update(EmergencySettings)
      .set({ coercionPinHash: hash })
      .where('id = :id', { id: settings.id })
      .execute();

    this.logger.log(`Coercion PIN set for user ${userId}`);
  }

  /**
   * Verifies a coercion PIN against the stored hash.
   * Used internally by the incidents module during cancel flow.
   */
  async verifyCoercionPin(userId: string, pin: string): Promise<boolean> {
    const settings = await this.settingsRepository
      .createQueryBuilder('settings')
      .addSelect('settings.coercionPinHash')
      .where('settings.userId = :userId', { userId })
      .getOne();

    if (!settings?.coercionPinHash) {
      return false;
    }

    return bcrypt.compare(pin, settings.coercionPinHash);
  }
}
