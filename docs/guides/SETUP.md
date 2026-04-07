# SafeCircle - Setup Guide

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Node.js | >= 18.x | Backend API, web apps |
| npm | >= 9.x | Package management |
| PostgreSQL | 16+ | Primary database |
| Redis | 7+ | Caching, BullMQ job queue |
| Flutter | >= 3.19 | Mobile app |
| Dart | >= 3.3 | Mobile app |
| Docker & Docker Compose | Latest | Local infrastructure |

Optional:

- **MinIO** (or any S3-compatible storage) for audio file storage
- **Twilio** account for SMS/voice alerts
- **Firebase** project for push notifications
- **Deepgram** API key for audio transcription

---

## Database Setup

### Option A: Docker (recommended)

```bash
cd infrastructure/docker
docker compose up -d postgres redis minio
```

This starts PostgreSQL 16 on port 5432, Redis 7 on port 6379, and MinIO on port 9000.

### Option B: Manual

1. Install PostgreSQL 16 and create a database:

```sql
CREATE USER safecircle WITH PASSWORD 'safecircle_dev';
CREATE DATABASE safecircle OWNER safecircle;
```

2. Install Redis 7 and start the server on the default port.

### Run migrations

```bash
cd backend-api
npm run migration:run
```

This executes the SQL in `src/database/migrations/001_initial_schema.sql` which creates all tables, enums, indexes, triggers, and seeds the initial feature flags.

### Seed data

```bash
cd backend-api
npm run seed
```

This creates:
- Admin user: `admin@safecircle.app` / `Admin123!`
- Test user: `user@safecircle.app` / `User123!`
- 3 trusted contacts for the test user
- Default emergency settings for the test user
- All 16 feature flags (Phase 1 enabled, Phase 2 disabled)

---

## Backend API Setup

```bash
cd backend-api
npm install
```

Create a `.env` file from the reference below, then start:

```bash
# Development with hot-reload
npm run start:dev

# Production build
npm run build
npm run start:prod
```

The API starts on `http://localhost:3000` by default. Swagger docs are available at `http://localhost:3000/api/docs` when running in development mode.

---

## Mobile App Setup (Flutter)

```bash
cd mobile-app
cp .env.example .env
```

Edit `.env` with your backend API URL and any API keys.

```bash
flutter pub get
flutter run
```

For iOS, ensure you have Xcode installed and CocoaPods:

```bash
cd ios && pod install && cd ..
flutter run -d ios
```

For Android, ensure you have Android Studio with an emulator or connected device:

```bash
flutter run -d android
```

---

## Admin Dashboard Setup

```bash
cd admin-web
npm install
```

Create `.env`:

```env
VITE_API_BASE_URL=http://localhost:3000/api/v1
VITE_WS_URL=ws://localhost:3000
```

```bash
npm run dev
```

The admin dashboard starts on `http://localhost:5173`.

---

## Contact Web View Setup

```bash
cd contact-web
npm install
```

Create `.env`:

```env
VITE_API_BASE_URL=http://localhost:3000/api/v1
VITE_WS_URL=ws://localhost:3000
VITE_MAPBOX_TOKEN=your_mapbox_token_here
```

```bash
npm run dev
```

The contact web view starts on `http://localhost:5174`.

---

## Environment Variables Reference

### Backend API (`backend-api/.env`)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `NODE_ENV` | No | `development` | Environment mode |
| `PORT` | No | `3000` | API server port |
| `API_PREFIX` | No | `api/v1` | URL prefix for all routes |
| `CORS_ORIGINS` | No | `http://localhost:3000` | Comma-separated allowed origins |
| `DB_HOST` | No | `localhost` | PostgreSQL host |
| `DB_PORT` | No | `5432` | PostgreSQL port |
| `DB_USERNAME` | No | `safecircle` | PostgreSQL user |
| `DB_PASSWORD` | Yes | - | PostgreSQL password |
| `DB_DATABASE` | No | `safecircle` | PostgreSQL database name |
| `DB_SSL` | No | `false` | Enable SSL for database |
| `DB_LOGGING` | No | `false` | Enable TypeORM query logging |
| `JWT_SECRET` | Yes | - | Secret for signing access tokens |
| `JWT_REFRESH_SECRET` | Yes | - | Secret for signing refresh tokens |
| `JWT_ACCESS_EXPIRES_IN` | No | `15m` | Access token TTL |
| `JWT_REFRESH_EXPIRES_IN` | No | `7d` | Refresh token TTL |
| `REDIS_HOST` | No | `localhost` | Redis host |
| `REDIS_PORT` | No | `6379` | Redis port |
| `REDIS_PASSWORD` | No | - | Redis password |
| `THROTTLE_TTL` | No | `60` | Rate limit window (seconds) |
| `THROTTLE_LIMIT` | No | `60` | Max requests per window |
| `AWS_S3_BUCKET` | No | - | S3 bucket for audio storage |
| `AWS_S3_REGION` | No | - | S3 region |
| `AWS_S3_ENDPOINT` | No | - | S3 endpoint (use for MinIO) |
| `AWS_ACCESS_KEY_ID` | No | - | S3 access key |
| `AWS_SECRET_ACCESS_KEY` | No | - | S3 secret key |
| `TWILIO_ACCOUNT_SID` | No | - | Twilio account SID |
| `TWILIO_AUTH_TOKEN` | No | - | Twilio auth token |
| `TWILIO_FROM_NUMBER` | No | - | Twilio sender phone number |
| `FIREBASE_PROJECT_ID` | No | - | Firebase project ID |
| `FIREBASE_PRIVATE_KEY` | No | - | Firebase service account key |
| `FIREBASE_CLIENT_EMAIL` | No | - | Firebase client email |
| `DEEPGRAM_API_KEY` | No | - | Deepgram API key for transcription |
| `CONTACT_TOKEN_EXPIRY_HOURS` | No | `24` | Contact access token TTL |
| `CONTACT_WEB_VIEW_BASE_URL` | No | `https://view.safecircle.app` | Contact web view base URL |

---

## Running Tests

### Backend unit tests

```bash
cd backend-api
npm run test           # Run once
npm run test:watch     # Watch mode
npm run test:cov       # With coverage
```

### Backend E2E tests

```bash
cd backend-api
npm run test:e2e
```

E2E tests require a running PostgreSQL and Redis instance (see Database Setup).

### Mobile app tests

```bash
cd mobile-app
flutter test
```

---

## Running Migrations

```bash
cd backend-api

# Run pending migrations
npm run migration:run

# Revert the last migration
npm run migration:revert

# Generate a new migration from entity changes
npm run migration:generate -- src/database/migrations/MigrationName
```
