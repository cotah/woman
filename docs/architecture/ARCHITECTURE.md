# SafeCircle Architecture

## System Overview

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Mobile App  │     │ Contact Web │     │  Admin Web  │
│   (Flutter)  │     │   (React)   │     │   (React)   │
└──────┬───────┘     └──────┬──────┘     └──────┬──────┘
       │                    │                    │
       └────────────┬───────┴────────────────────┘
                    │
            ┌───────▼────────┐
            │   API Gateway  │
            │   (NestJS)     │
            │  REST + WS     │
            └───────┬────────┘
                    │
       ┌────────────┼────────────┐
       │            │            │
┌──────▼──┐  ┌─────▼────┐ ┌────▼─────┐
│PostgreSQL│  │  Redis    │ │ S3/Minio │
│  (data)  │  │(cache/q)  │ │ (files)  │
└──────────┘  └──────────┘ └──────────┘
                    │
            ┌───────▼────────┐
            │  Queue Workers │
            │  (BullMQ)      │
            ├────────────────┤
            │ • Alert dispatch│
            │ • Audio process │
            │ • AI pipeline   │
            │ • Retry engine  │
            └────────────────┘
                    │
       ┌────────────┼────────────┐
       │            │            │
┌──────▼──┐  ┌─────▼────┐ ┌────▼─────┐
│  Twilio  │  │   FCM    │ │ Deepgram │
│(SMS/Voice│  │  + APNs  │ │ + OpenAI │
└──────────┘  └──────────┘ └──────────┘
```

## Core Design Decisions

### 1. Event-Sourced Incident Timeline
Incidents use an append-only event model. Every state change, location update, notification, and response is recorded as an immutable event. This provides:
- Full audit trail
- Replay capability
- Evidence-grade timeline

### 2. Deterministic Risk Engine (Phase 1)
Risk scoring is rule-based and configuration-driven. Every score change includes the rule that triggered it and the reason. This ensures:
- Explainability
- Auditability
- No black-box decisions for emergency activation

The engine exposes a clean interface so Phase 2 can add ML-based scoring alongside or as replacement.

### 3. Progressive Alert Escalation
Alerts use wave-based dispatch through a queue system:
- Wave 1: Push + SMS to priority contacts (immediate)
- Wave 2: Push + SMS + Voice to broader contacts (after timeout)
- Wave 3: Full escalation (after further timeout)

Each wave is a separate queued job with retry logic.

### 4. Coercion-Aware Architecture
The coercion system is deeply integrated:
- Dual PIN paths at authentication level
- Separate UI state machine branches
- Silent escalation through the same incident pipeline
- Coercion events are audit-logged but not visible on device

### 5. Provider Abstraction
All external services (SMS, push, voice, STT, AI) are behind interfaces:
```typescript
interface AlertChannelProvider {
  send(alert: AlertPayload): Promise<DeliveryResult>;
  getStatus(deliveryId: string): Promise<DeliveryStatus>;
}
```
This allows provider swapping, failover, and Phase 2 multi-provider support.

### 6. Offline-First Mobile
The mobile app maintains local incident state:
- Incidents are created locally first
- Events queue for upload
- Location updates buffer locally
- Audio chunks persist to local storage
- Sync engine pushes when connectivity returns

### 7. Feature Flag Gating
All Phase 2 touchpoints are gated behind feature flags:
- Database columns exist but are unused
- Service interfaces are defined but implementations are stubs
- UI components have conditional rendering paths
- API endpoints exist but return 404 when flag is off

## Service Boundaries

```
AuthModule          — registration, login, sessions, coercion PIN
UsersModule         — profile, devices, preferences
ContactsModule      — trusted contacts CRUD, verification, permissions
SettingsModule      — emergency settings, audio prefs, trigger config
IncidentsModule     — incident lifecycle, events, resolution
RiskEngineModule    — scoring rules, evaluation, level determination
TimelineModule      — event aggregation, timeline rendering
LocationModule      — live location ingestion, trail storage
AudioModule         — upload, storage, metadata, transcription hooks
NotificationsModule — alert dispatch, wave orchestration, delivery tracking
AuditModule         — append-only audit log, query interface
AdminModule         — admin endpoints, dashboard data, feature flags
HealthModule        — system health, provider status
```

## Data Flow: Emergency Activation

```
1. User triggers emergency (button / coercion PIN / shortcut)
2. Mobile creates local incident record
3. POST /incidents → backend creates incident
4. Risk engine evaluates trigger → initial score
5. Silent countdown begins (mobile-side timer)
6. If not cancelled within window:
   a. Incident transitions to ACTIVE
   b. Notification orchestrator dispatches Wave 1
   c. Location streaming begins (WS or polling)
   d. Audio recording begins (if consented)
   e. Audio chunks upload to S3 via /incidents/:id/audio
   f. Transcription jobs queue
   g. Risk engine re-evaluates on new signals
7. Contacts receive alert → open contact web view
8. Contact responses flow back → timeline updated
9. Escalation waves fire on timeout if no response
10. Incident resolves when user ends or policy timeout
```

## Phase 2 Extension Points

| Feature | Extension Point |
|---------|----------------|
| Wearable triggers | TriggerProvider interface + device registry |
| Disguised UI | AppModeService + theme switcher |
| AI risk engine | RiskScoringStrategy interface (strategy pattern) |
| Geofencing | LocationPolicyService + geofence entity |
| Route anomaly | RouteAnalysisService + baseline model |
| Human ops | EscalationTarget interface + operator queue |
| Org mode | TenantService + org entity + RBAC |
| Subscriptions | PlanService + entitlement checks |
