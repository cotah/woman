import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, IsNull } from 'typeorm';
import { ConfigService } from '@nestjs/config';
import { randomBytes, createHash } from 'crypto';
import { ContactAccessToken } from './entities/contact-access-token.entity';

export interface ValidatedTokenData {
  tokenId: string;
  incidentId: string;
  contactId: string;
}

@Injectable()
export class ContactAccessService {
  private readonly logger = new Logger(ContactAccessService.name);
  private readonly tokenExpiryHours: number;
  private readonly webViewBaseUrl: string;

  constructor(
    @InjectRepository(ContactAccessToken)
    private readonly tokenRepo: Repository<ContactAccessToken>,
    private readonly config: ConfigService,
  ) {
    this.tokenExpiryHours = this.config.get<number>(
      'CONTACT_TOKEN_EXPIRY_HOURS',
      24,
    );
    this.webViewBaseUrl = this.config.get<string>(
      'CONTACT_WEB_VIEW_BASE_URL',
      'https://view.safecircle.app',
    );
  }

  /**
   * Generate a secure access token for a trusted contact to view an incident.
   * Returns the raw token (to be sent to the contact) and the full access URL.
   */
  async generateToken(
    incidentId: string,
    contactId: string,
  ): Promise<{ rawToken: string; accessUrl: string }> {
    // Generate a crypto-random token (48 bytes = 64 chars base64url)
    const rawToken = randomBytes(48).toString('base64url');

    // Hash the token for storage (never store raw tokens)
    const tokenHash = this.hashToken(rawToken);

    const expiresAt = new Date();
    expiresAt.setHours(expiresAt.getHours() + this.tokenExpiryHours);

    // Revoke any existing active tokens for this contact+incident pair
    await this.revokeExistingTokens(incidentId, contactId);

    // Create the new token
    const token = this.tokenRepo.create({
      incidentId,
      contactId,
      tokenHash,
      expiresAt,
    });

    await this.tokenRepo.save(token);

    const accessUrl = `${this.webViewBaseUrl}/incident/${incidentId}?token=${rawToken}`;

    this.logger.log(
      `Access token generated for contact ${contactId} on incident ${incidentId} | ` +
        `expires ${expiresAt.toISOString()}`,
    );

    return { rawToken, accessUrl };
  }

  /**
   * Validate an access token. Returns the associated incident and contact IDs,
   * or null if the token is invalid, expired, or revoked.
   */
  async validateToken(rawToken: string): Promise<ValidatedTokenData | null> {
    if (!rawToken || rawToken.length < 10) {
      return null;
    }

    const tokenHash = this.hashToken(rawToken);

    const tokenRecord = await this.tokenRepo.findOne({
      where: {
        tokenHash,
        revokedAt: IsNull(),
      },
    });

    if (!tokenRecord) {
      this.logger.debug('Token validation failed: token not found');
      return null;
    }

    // Check expiry
    if (new Date() > tokenRecord.expiresAt) {
      this.logger.debug(
        `Token validation failed: expired at ${tokenRecord.expiresAt.toISOString()}`,
      );
      return null;
    }

    // Mark as used (first access tracking)
    if (!tokenRecord.usedAt) {
      await this.tokenRepo.update(tokenRecord.id, { usedAt: new Date() });
    }

    return {
      tokenId: tokenRecord.id,
      incidentId: tokenRecord.incidentId,
      contactId: tokenRecord.contactId,
    };
  }

  /**
   * Revoke all active tokens for a specific incident (e.g. when incident is resolved).
   */
  async revokeTokensByIncident(incidentId: string): Promise<number> {
    const result = await this.tokenRepo.update(
      {
        incidentId,
        revokedAt: IsNull(),
      },
      { revokedAt: new Date() },
    );

    const count = result.affected || 0;
    if (count > 0) {
      this.logger.log(
        `Revoked ${count} access tokens for incident ${incidentId}`,
      );
    }

    return count;
  }

  /**
   * Revoke all active tokens for a specific contact on a specific incident.
   */
  async revokeExistingTokens(
    incidentId: string,
    contactId: string,
  ): Promise<void> {
    await this.tokenRepo.update(
      {
        incidentId,
        contactId,
        revokedAt: IsNull(),
      },
      { revokedAt: new Date() },
    );
  }

  /**
   * Get all active (non-revoked, non-expired) tokens for an incident.
   */
  async getActiveTokensByIncident(
    incidentId: string,
  ): Promise<ContactAccessToken[]> {
    const now = new Date();

    return this.tokenRepo
      .createQueryBuilder('token')
      .where('token.incident_id = :incidentId', { incidentId })
      .andWhere('token.revoked_at IS NULL')
      .andWhere('token.expires_at > :now', { now })
      .orderBy('token.created_at', 'ASC')
      .getMany();
  }

  // ------------------------------------------------------------------
  // Private
  // ------------------------------------------------------------------

  /**
   * Hash a raw token using SHA-256.
   * We store only the hash so a database breach does not expose valid tokens.
   */
  private hashToken(rawToken: string): string {
    return createHash('sha256').update(rawToken).digest('hex');
  }
}
