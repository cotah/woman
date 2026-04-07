# SafeCircle - Personal Safety Platform

A production-grade personal safety platform for iOS and Android with backend services and web dashboards.

## Mission

Provide immediate, reliable, and discreet emergency support through trusted contact networks. The platform detects risk signals, records context, notifies trusted contacts, and supports rapid response.

**Important:** This platform does NOT judge legal truth, does NOT accuse third parties. It records factual events and facilitates rapid safety response.

## Architecture

- **mobile-app/** — Flutter app (iOS + Android)
- **backend-api/** — NestJS REST + WebSocket API
- **admin-web/** — React admin operations dashboard
- **contact-web/** — React secure incident view for trusted contacts
- **shared-types/** — Shared TypeScript type definitions
- **infrastructure/** — Docker, Terraform, K8s configs
- **docs/** — Architecture docs, ADRs, API docs, guides

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Mobile | Flutter (Dart) |
| Backend | Node.js + NestJS |
| Database | PostgreSQL |
| Cache/Queue | Redis + BullMQ |
| Storage | S3-compatible |
| Push | FCM + APNs |
| SMS/Voice | Twilio |
| Maps | Mapbox |
| Speech-to-text | Deepgram |
| AI/LLM | OpenAI (classification/summarization) |
| Admin/Contact Web | React + TypeScript + Vite |

## Quick Start

### Prerequisites

- Node.js 20+
- Flutter 3.19+
- PostgreSQL 16+
- Redis 7+
- Docker (optional)

### Backend

```bash
cd backend-api
cp .env.example .env
npm install
npm run migration:run
npm run seed
npm run start:dev
```

### Mobile App

```bash
cd mobile-app
cp .env.example .env
flutter pub get
flutter run
```

### Admin Dashboard

```bash
cd admin-web
cp .env.example .env
npm install
npm run dev
```

### Contact Web View

```bash
cd contact-web
cp .env.example .env
npm install
npm run dev
```

## Phase Strategy

**Phase 1** (Current): Core emergency activation, trusted contacts, live location, audio recording, risk scoring, admin dashboard.

**Phase 2** (Planned): Wearable triggers, disguised interfaces, advanced AI, geofencing, route anomaly detection, organization mode, human-assisted operations.

## Key Design Principles

1. Speed — sub-second trigger to incident creation
2. Discretion — silent operation, coercion-aware flows
3. Reliability — retry logic, queue-based alerts, offline-first mobile
4. Auditability — immutable timeline, append-only audit logs
5. Progressive escalation — layered alert waves
6. Privacy by design — consent-gated features, minimal data exposure
7. Neutral language — no accusatory content, factual event recording

## License

Proprietary. All rights reserved.
