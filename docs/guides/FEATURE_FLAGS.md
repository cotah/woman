# Feature Flags

SafeCircle uses feature flags to control the rollout of functionality across phases. Flags are stored in the `feature_flags` table and can be toggled at runtime via the admin API.

---

## Flag Schema

Each flag has the following fields:

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Primary key |
| `key` | VARCHAR(100) | Unique machine-readable identifier |
| `name` | VARCHAR(200) | Human-readable display name |
| `description` | TEXT | Explanation of what the flag controls |
| `enabled` | BOOLEAN | Whether the flag is currently active |
| `phase` | INTEGER | The project phase this flag belongs to |
| `metadata` | JSONB | Additional configuration data |

---

## Phase 1 Flags (Enabled by Default)

These flags are enabled at initial deployment and control core safety features.

| Key | Name | Description |
|-----|------|-------------|
| `audio_recording` | Audio Recording | Enable audio recording during incidents. When disabled, the mobile app will not start recording even if the user's settings allow it. |
| `audio_ai_analysis` | Audio AI Analysis | Enable AI-powered audio analysis (transcription + distress detection). Requires `audio_recording` to also be enabled. |
| `sms_alerts` | SMS Alerts | Enable SMS alert delivery to trusted contacts. When disabled, the notification service skips the SMS channel. |
| `push_alerts` | Push Notifications | Enable push notification alerts via Firebase Cloud Messaging. |
| `voice_call_alerts` | Voice Call Alerts | Enable voice call alert delivery via Twilio. This is the highest-urgency channel. |
| `coercion_mode` | Coercion Mode | Enable the coercion PIN functionality. When disabled, the coercion PIN setting is hidden in the app and coercion-related logic is bypassed. |
| `test_mode` | Test Mode | Enable incident simulation mode. Allows users to trigger test incidents that do not dispatch real alerts to contacts. |

---

## Phase 2 Flags (Disabled by Default)

These flags control upcoming features that are not yet fully implemented. They are seeded as disabled and should only be enabled once the corresponding backend and mobile code is complete.

| Key | Name | Description |
|-----|------|-------------|
| `wearable_triggers` | Wearable Triggers | Enable smartwatch trigger support (Apple Watch, Wear OS). Requires the wearable companion app. |
| `disguised_interface` | Disguised Interface | Enable the fake calculator / disguised app mode so the app can be opened covertly. |
| `ai_risk_engine` | AI Risk Engine | Replace the rule-based risk scoring with an ML-based model. The ML model implements the same `RiskScoringStrategy` interface. |
| `geofencing` | Geofencing | Enable geofence-based alerts. Users can define safe zones and danger zones; crossing a boundary can auto-trigger an incident. |
| `route_anomaly` | Route Anomaly Detection | Enable route deviation detection. The system learns expected routes and triggers alerts on significant deviations. |
| `org_mode` | Organization Mode | Enable campus/enterprise features (organizations, org admins, bulk user management). |
| `human_operators` | Human Operators | Enable the human-assisted response center. Operators can monitor active incidents and take direct action. |
| `silent_challenge` | Silent Challenge-Response | Enable silent safety check flows. The system periodically prompts the user for a silent confirmation; failure to respond can trigger an alert. |
| `evidence_export` | Evidence Package Export | Enable incident evidence export. Generates a downloadable package with timeline, audio, transcripts, locations, and risk assessments. |

---

## Admin API

### List all flags

```
GET /api/v1/admin/feature-flags
Authorization: Bearer <admin_token>
```

Returns all feature flags ordered by phase and key.

### Toggle a flag

```
PATCH /api/v1/admin/feature-flags/:id
Authorization: Bearer <admin_token>
Content-Type: application/json

{ "enabled": true }
```

Toggles the flag and creates an audit log entry.

---

## Usage in Code

### Backend (NestJS)

The `FeatureFlagsService` provides a method to check if a flag is enabled:

```typescript
const isEnabled = await this.featureFlagsService.isEnabled('audio_recording');

if (isEnabled) {
  // proceed with audio recording logic
}
```

Flags are cached in Redis with a short TTL to avoid hitting the database on every check.

### Mobile App (Flutter)

The mobile app fetches feature flags on login and caches them locally. Flags are refreshed periodically and on app resume. The app uses the flags to show/hide UI elements and enable/disable functionality.

---

## Adding a New Flag

1. Add an `INSERT` statement to the seed script (`backend-api/src/database/seeds/run-seed.ts`).
2. Add the flag to the SQL migration if it should exist on fresh deployments.
3. Reference the flag key in backend services via `FeatureFlagsService.isEnabled()`.
4. Reference the flag in the mobile app's feature flag provider.
5. Document the flag in this file.
