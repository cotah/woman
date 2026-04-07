import {
  Injectable,
  UnauthorizedException,
  Logger,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, IsNull } from 'typeorm';
import * as bcrypt from 'bcrypt';
import * as crypto from 'crypto';
import { UsersService } from '../users/users.service';
import { UserSession } from '../users/entities/user-session.entity';
import { User } from '../users/entities/user.entity';
import { RegisterDto } from './dto/register.dto';
import { LoginDto } from './dto/login.dto';
import { JwtPayload } from '@/common/interfaces/request-context';

export interface TokenPair {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

export interface AuthResponse {
  user: {
    id: string;
    email: string;
    firstName: string;
    lastName: string;
    role: string;
  };
  tokens: TokenPair;
}

@Injectable()
export class AuthService {
  private readonly logger = new Logger(AuthService.name);

  constructor(
    private readonly usersService: UsersService,
    private readonly jwtService: JwtService,
    private readonly configService: ConfigService,
    @InjectRepository(UserSession)
    private readonly sessionsRepository: Repository<UserSession>,
  ) {}

  async register(dto: RegisterDto): Promise<AuthResponse> {
    const user = await this.usersService.create({
      email: dto.email,
      password: dto.password,
      firstName: dto.firstName,
      lastName: dto.lastName,
      phone: dto.phone,
    });

    const tokens = await this.issueTokens(user);

    this.logger.log(`User registered: ${user.id}`);

    return {
      user: {
        id: user.id,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        role: user.role,
      },
      tokens,
    };
  }

  async login(dto: LoginDto, ip?: string, userAgent?: string): Promise<AuthResponse> {
    const user = await this.usersService.findByEmail(dto.email);

    if (!user) {
      throw new UnauthorizedException('Invalid email or password');
    }

    if (!user.isActive) {
      throw new UnauthorizedException('Account is deactivated');
    }

    const isPasswordValid = await this.usersService.validatePassword(
      user,
      dto.password,
    );

    if (!isPasswordValid) {
      throw new UnauthorizedException('Invalid email or password');
    }

    await this.usersService.updateLastLogin(user.id);

    const tokens = await this.issueTokens(user, {
      ip,
      userAgent,
      deviceId: dto.deviceId,
    });

    this.logger.log(`User logged in: ${user.id}`);

    return {
      user: {
        id: user.id,
        email: user.email,
        firstName: user.firstName,
        lastName: user.lastName,
        role: user.role,
      },
      tokens,
    };
  }

  async refreshTokens(refreshToken: string): Promise<TokenPair> {
    const tokenHash = this.hashToken(refreshToken);

    const session = await this.sessionsRepository.findOne({
      where: {
        refreshTokenHash: tokenHash,
        revokedAt: IsNull(),
      },
      relations: ['user'],
    });

    if (!session) {
      throw new UnauthorizedException('Invalid refresh token');
    }

    if (session.expiresAt < new Date()) {
      await this.sessionsRepository.update(session.id, {
        revokedAt: new Date(),
      });
      throw new UnauthorizedException('Refresh token has expired');
    }

    if (!session.user || !session.user.isActive) {
      throw new UnauthorizedException('User account is deactivated');
    }

    // Rotate: revoke old session, issue new tokens
    await this.sessionsRepository.update(session.id, {
      revokedAt: new Date(),
    });

    return this.issueTokens(session.user, {
      ip: session.ipAddress ?? undefined,
      userAgent: session.userAgent ?? undefined,
      deviceId: session.deviceId ?? undefined,
    });
  }

  async logout(userId: string, refreshToken?: string): Promise<void> {
    if (refreshToken) {
      const tokenHash = this.hashToken(refreshToken);
      await this.sessionsRepository.update(
        { refreshTokenHash: tokenHash, userId },
        { revokedAt: new Date() },
      );
    } else {
      // Revoke all sessions for this user
      await this.sessionsRepository
        .createQueryBuilder()
        .update()
        .set({ revokedAt: new Date() })
        .where('user_id = :userId AND revoked_at IS NULL', { userId })
        .execute();
    }

    this.logger.log(`User logged out: ${userId}`);
  }

  private async issueTokens(
    user: User,
    sessionMeta?: {
      ip?: string;
      userAgent?: string;
      deviceId?: string;
    },
  ): Promise<TokenPair> {
    const payload: JwtPayload = {
      sub: user.id,
      email: user.email,
      role: user.role,
    };

    const accessExpiresIn = this.configService.get<string>(
      'app.jwt.accessExpiresIn',
      '15m',
    );
    const refreshExpiresIn = this.configService.get<string>(
      'app.jwt.refreshExpiresIn',
      '7d',
    );

    const accessToken = this.jwtService.sign(payload, {
      secret: this.configService.get<string>('app.jwt.secret'),
      expiresIn: accessExpiresIn,
    });

    const refreshToken = crypto.randomBytes(64).toString('hex');
    const refreshTokenHash = this.hashToken(refreshToken);

    // Parse refresh expiry for session record
    const refreshExpiresMs = this.parseDuration(refreshExpiresIn);
    const expiresAt = new Date(Date.now() + refreshExpiresMs);

    const session = this.sessionsRepository.create({
      userId: user.id,
      refreshTokenHash,
      deviceId: sessionMeta?.deviceId ?? null,
      ipAddress: sessionMeta?.ip ?? null,
      userAgent: sessionMeta?.userAgent ?? null,
      expiresAt,
    });

    await this.sessionsRepository.save(session);

    return {
      accessToken,
      refreshToken,
      expiresIn: this.parseDuration(accessExpiresIn) / 1000,
    };
  }

  private hashToken(token: string): string {
    return crypto.createHash('sha256').update(token).digest('hex');
  }

  private parseDuration(duration: string): number {
    const match = duration.match(/^(\d+)([smhd])$/);
    if (!match) return 900_000; // default 15m

    const value = parseInt(match[1], 10);
    const unit = match[2];

    switch (unit) {
      case 's':
        return value * 1000;
      case 'm':
        return value * 60 * 1000;
      case 'h':
        return value * 60 * 60 * 1000;
      case 'd':
        return value * 24 * 60 * 60 * 1000;
      default:
        return 900_000;
    }
  }
}
