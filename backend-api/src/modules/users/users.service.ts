import {
  Injectable,
  NotFoundException,
  ConflictException,
  Logger,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { User } from './entities/user.entity';
import {
  DevicePlatform,
  UserDevice,
} from './entities/user-device.entity';

const BCRYPT_ROUNDS = 12;

@Injectable()
export class UsersService {
  private readonly logger = new Logger(UsersService.name);

  constructor(
    @InjectRepository(User)
    private readonly usersRepository: Repository<User>,
    @InjectRepository(UserDevice)
    private readonly devicesRepository: Repository<UserDevice>,
  ) {}

  async findById(id: string): Promise<User | null> {
    return this.usersRepository.findOne({ where: { id } });
  }

  async findByEmail(email: string): Promise<User | null> {
    return this.usersRepository.findOne({ where: { email: email.toLowerCase() } });
  }

  async create(data: {
    email: string;
    password: string;
    firstName: string;
    lastName: string;
    phone?: string;
  }): Promise<User> {
    const normalizedEmail = data.email.toLowerCase().trim();

    const existing = await this.findByEmail(normalizedEmail);
    if (existing) {
      throw new ConflictException('An account with this email already exists');
    }

    const passwordHash = await bcrypt.hash(data.password, BCRYPT_ROUNDS);

    const user = this.usersRepository.create({
      email: normalizedEmail,
      passwordHash,
      firstName: data.firstName.trim(),
      lastName: data.lastName.trim(),
      phone: data.phone || null,
    });

    const saved = await this.usersRepository.save(user);
    this.logger.log(`User created: ${saved.id}`);
    return saved;
  }

  async validatePassword(user: User, password: string): Promise<boolean> {
    return bcrypt.compare(password, user.passwordHash);
  }

  async updateLastLogin(userId: string): Promise<void> {
    await this.usersRepository.update(userId, { lastLoginAt: new Date() });
  }

  async updateProfile(
    userId: string,
    data: Partial<Pick<User, 'firstName' | 'lastName' | 'phone'>>,
  ): Promise<User> {
    const user = await this.findById(userId);
    if (!user) {
      throw new NotFoundException('User not found');
    }

    if (data.firstName !== undefined) user.firstName = data.firstName.trim();
    if (data.lastName !== undefined) user.lastName = data.lastName.trim();
    if (data.phone !== undefined) user.phone = data.phone || null;

    return this.usersRepository.save(user);
  }

  async softDelete(userId: string): Promise<void> {
    const user = await this.findById(userId);
    if (!user) {
      throw new NotFoundException('User not found');
    }

    await this.usersRepository.softDelete(userId);
    this.logger.log(`User soft-deleted: ${userId}`);
  }

  async deactivate(userId: string): Promise<void> {
    await this.usersRepository.update(userId, { isActive: false });
    this.logger.log(`User deactivated: ${userId}`);
  }

  // ──────────────────────────────────────────────────────────
  // Device registration (FCM / APNs push tokens)
  // ──────────────────────────────────────────────────────────

  /**
   * Register or refresh a device for a user.
   *
   * Idempotent UPSERT keyed on (user_id, push_token). If the same
   * device calls again (e.g. on every login or after a token rotation),
   * we update last_seen_at, mark active, and refresh telemetry fields.
   *
   * Relies on the partial UNIQUE index from migration 005:
   *   idx_user_devices_user_pushtoken_unique ON (user_id, push_token).
   */
  async registerDevice(params: {
    userId: string;
    platform: DevicePlatform;
    pushToken: string;
    deviceModel?: string;
    osVersion?: string;
    appVersion?: string;
  }): Promise<UserDevice> {
    const {
      userId,
      platform,
      pushToken,
      deviceModel,
      osVersion,
      appVersion,
    } = params;

    // Try to find an existing device for this (user, token) pair.
    const existing = await this.devicesRepository.findOne({
      where: { userId, pushToken },
    });

    if (existing) {
      existing.platform = platform;
      existing.isActive = true;
      existing.lastSeenAt = new Date();
      if (deviceModel !== undefined) existing.deviceModel = deviceModel;
      if (osVersion !== undefined) existing.osVersion = osVersion;
      if (appVersion !== undefined) existing.appVersion = appVersion;
      const saved = await this.devicesRepository.save(existing);
      this.logger.log(
        `Device refreshed | user=${userId} | platform=${platform} | id=${saved.id}`,
      );
      return saved;
    }

    const device = this.devicesRepository.create({
      userId,
      platform,
      pushToken,
      deviceToken: null,
      deviceModel: deviceModel ?? null,
      osVersion: osVersion ?? null,
      appVersion: appVersion ?? null,
      isActive: true,
      lastSeenAt: new Date(),
    });

    try {
      const saved = await this.devicesRepository.save(device);
      this.logger.log(
        `Device registered | user=${userId} | platform=${platform} | id=${saved.id}`,
      );
      return saved;
    } catch (error) {
      // 23505 = UniqueViolation (race between findOne and save).
      if (error?.code === '23505') {
        const fallback = await this.devicesRepository.findOneOrFail({
          where: { userId, pushToken },
        });
        fallback.isActive = true;
        fallback.lastSeenAt = new Date();
        return this.devicesRepository.save(fallback);
      }
      throw error;
    }
  }

  /** Remove a device explicitly (e.g. user pressed "sign out everywhere"). */
  async deleteDevice(userId: string, deviceId: string): Promise<void> {
    const device = await this.devicesRepository.findOne({
      where: { id: deviceId, userId },
    });
    if (!device) {
      throw new NotFoundException('Device not found');
    }
    await this.devicesRepository.delete(deviceId);
    this.logger.log(`Device deleted | user=${userId} | id=${deviceId}`);
  }

  /**
   * Mark a device inactive when FCM reports the token is no longer
   * registered. Called by PushProvider via the onInvalidToken hook.
   */
  async markDeviceInactiveByToken(pushToken: string): Promise<void> {
    if (!pushToken) return;
    const result = await this.devicesRepository.update(
      { pushToken },
      { isActive: false },
    );
    if (result.affected && result.affected > 0) {
      this.logger.warn(
        `Marked ${result.affected} device(s) inactive (token rejected by FCM)`,
      );
    }
  }

  /**
   * Returns the most recently seen active device for a user, or null
   * if none. Used by NotificationsService.sendSafetyCheckin to push
   * directly to the user.
   */
  async findMostRecentActiveDevice(
    userId: string,
  ): Promise<UserDevice | null> {
    return this.devicesRepository.findOne({
      where: { userId, isActive: true },
      order: { lastSeenAt: 'DESC' },
    });
  }

  /**
   * Best-effort lookup of a contact's push token by phone number.
   *
   * Used by IncidentsService to populate TrustedContactInfo.pushToken
   * when dispatching alert waves, so a contact who is also a SafeCircle
   * user gets a push instead of just SMS. Returns null when:
   *   - no SafeCircle user has that phone
   *   - that user has no active device with a push_token
   *
   * Phone matching is exact-string only — both sides are stored in
   * E.164 (the contact form validates it; the user profile DTO
   * enforces the same regex). No normalization is attempted here.
   */
  async findActivePushTokenByPhone(phone: string): Promise<string | null> {
    if (!phone) return null;
    const row: { push_token: string | null }[] = await this.devicesRepository
      .createQueryBuilder('device')
      .innerJoin(User, 'user', 'user.id = device.user_id')
      .where('user.phone = :phone', { phone })
      .andWhere('device.is_active = true')
      .andWhere('device.push_token IS NOT NULL')
      .orderBy('device.last_seen_at', 'DESC')
      .limit(1)
      .select('device.push_token', 'push_token')
      .getRawMany();

    return row[0]?.push_token ?? null;
  }
}
