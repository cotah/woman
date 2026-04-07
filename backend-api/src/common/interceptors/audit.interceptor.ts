import {
  Injectable,
  NestInterceptor,
  ExecutionContext,
  CallHandler,
  Logger,
} from '@nestjs/common';
import { Observable } from 'rxjs';
import { tap } from 'rxjs/operators';
import { Request } from 'express';
import { AuthenticatedUser } from '../interfaces/request-context';

@Injectable()
export class AuditInterceptor implements NestInterceptor {
  private readonly logger = new Logger('AuditLog');

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    const request = context.switchToHttp().getRequest<Request>();
    const { method, url, ip } = request;
    const userAgent = request.get('user-agent') || 'unknown';
    const user = request.user as AuthenticatedUser | undefined;
    const startTime = Date.now();

    return next.handle().pipe(
      tap({
        next: () => {
          const duration = Date.now() - startTime;
          const statusCode = context.switchToHttp().getResponse().statusCode;

          if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(method)) {
            this.logger.log(
              JSON.stringify({
                type: 'audit',
                userId: user?.id || 'anonymous',
                action: `${method} ${url}`,
                statusCode,
                duration,
                ip,
                userAgent,
                timestamp: new Date().toISOString(),
              }),
            );
          }
        },
        error: (error) => {
          const duration = Date.now() - startTime;

          this.logger.warn(
            JSON.stringify({
              type: 'audit_error',
              userId: user?.id || 'anonymous',
              action: `${method} ${url}`,
              error: error.message,
              duration,
              ip,
              userAgent,
              timestamp: new Date().toISOString(),
            }),
          );
        },
      }),
    );
  }
}
