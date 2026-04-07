import * as Sentry from '@sentry/nestjs';

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  environment: process.env.NODE_ENV || 'development',
  // Only send errors in production/staging
  enabled: process.env.NODE_ENV !== 'development',
  sendDefaultPii: true,
  tracesSampleRate: 0.2,
});
