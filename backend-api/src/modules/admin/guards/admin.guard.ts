import {
  Injectable,
  CanActivate,
  ExecutionContext,
  ForbiddenException,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { AuthenticatedUser } from '@/common/interfaces/request-context';

/**
 * Composite guard: validates JWT first, then checks for admin/super_admin role.
 *
 * Usage: @UseGuards(AdminGuard)
 * This is equivalent to stacking JwtAuthGuard + a role check, but combined
 * into a single guard for clarity on admin routes.
 */
@Injectable()
export class AdminGuard extends AuthGuard('jwt') {
  handleRequest<TUser = AuthenticatedUser>(
    err: Error | null,
    user: TUser,
    _info: Error | undefined,
    context: ExecutionContext,
  ): TUser {
    if (err || !user) {
      throw err || new ForbiddenException('Authentication required');
    }

    const authenticatedUser = user as unknown as AuthenticatedUser;
    const allowedRoles = ['admin', 'super_admin'];

    if (!allowedRoles.includes(authenticatedUser.role)) {
      throw new ForbiddenException(
        'Access denied. Admin or super_admin role required.',
      );
    }

    return user;
  }
}
