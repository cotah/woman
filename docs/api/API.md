# SafeCircle API Reference

Base URL: `/api/v1`

All authenticated endpoints require a `Bearer` token in the `Authorization` header unless marked as **Public**.

---

## Health

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/health` | Public | Basic liveness check |
| GET | `/health/detailed` | Public | Readiness check (DB, Redis, S3) |

### GET /health

**Response 200:**
```json
{
  "status": "ok",
  "timestamp": "2026-04-06T12:00:00.000Z"
}
```

### GET /health/detailed

**Response 200:**
```json
{
  "status": "ok",
  "timestamp": "2026-04-06T12:00:00.000Z",
  "services": {
    "database": "ok",
    "redis": "ok",
    "s3": "ok"
  }
}
```

---

## Auth

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/auth/register` | Public | Register a new user |
| POST | `/auth/login` | Public | Login with email/password |
| POST | `/auth/refresh` | Public | Refresh access token |
| POST | `/auth/logout` | Bearer | Logout and revoke refresh token |

### POST /auth/register

**Request:**
```json
{
  "email": "user@example.com",
  "password": "SecurePass123!",
  "firstName": "Jane",
  "lastName": "Doe",
  "phone": "+1234567890"
}
```

**Response 201:**
```json
{
  "accessToken": "eyJ...",
  "refreshToken": "eyJ...",
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "firstName": "Jane",
    "lastName": "Doe",
    "role": "user"
  }
}
```

**Errors:** 409 Email already exists.

### POST /auth/login

**Request:**
```json
{
  "email": "user@example.com",
  "password": "SecurePass123!"
}
```

**Response 200:** Same shape as register response.

**Errors:** 401 Invalid credentials.

### POST /auth/refresh

**Request:**
```json
{
  "refreshToken": "eyJ..."
}
```

**Response 200:**
```json
{
  "accessToken": "eyJ...",
  "refreshToken": "eyJ..."
}
```

**Errors:** 401 Invalid or expired refresh token.

### POST /auth/logout

**Request:**
```json
{
  "refreshToken": "eyJ..."
}
```

**Response:** 204 No Content.

---

## Users

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/users/me` | Bearer | Get current user profile |
| PATCH | `/users/me` | Bearer | Update current user profile |
| DELETE | `/users/me` | Bearer | Soft-delete current user account |

### GET /users/me

**Response 200:**
```json
{
  "id": "uuid",
  "email": "user@example.com",
  "firstName": "Jane",
  "lastName": "Doe",
  "phone": "+1234567890",
  "role": "user",
  "isActive": true,
  "onboardingCompleted": true,
  "emailVerified": true,
  "lastLoginAt": "2026-04-06T12:00:00.000Z",
  "createdAt": "2026-01-01T00:00:00.000Z"
}
```

### PATCH /users/me

**Request:**
```json
{
  "firstName": "Janet",
  "lastName": "Smith",
  "phone": "+1987654321"
}
```

All fields are optional. Phone must be E.164 format.

**Response 200:** Updated user object.

### DELETE /users/me

**Response:** 204 No Content. Performs a soft delete.

---

## Contacts

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/contacts` | Bearer | List all trusted contacts |
| GET | `/contacts/:id` | Bearer | Get a single contact |
| POST | `/contacts` | Bearer | Create a trusted contact |
| PATCH | `/contacts/:id` | Bearer | Update a trusted contact |
| DELETE | `/contacts/:id` | Bearer | Soft-delete a trusted contact |

### POST /contacts

**Request:**
```json
{
  "name": "Alice Johnson",
  "relationship": "Sister",
  "phone": "+15550000010",
  "email": "alice@example.com",
  "priority": 1,
  "canReceiveSms": true,
  "canReceivePush": false,
  "canReceiveVoiceCall": true,
  "canAccessAudio": false,
  "canAccessLocation": true,
  "locale": "en"
}
```

**Response 201:** Contact object with generated `id`.

### PATCH /contacts/:id

**Request:** Any subset of the fields from POST.

**Response 200:** Updated contact object.

### DELETE /contacts/:id

**Response:** 204 No Content.

---

## Settings

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/settings/emergency` | Bearer | Get emergency settings |
| PATCH | `/settings/emergency` | Bearer | Update emergency settings |
| POST | `/settings/emergency/coercion-pin` | Bearer | Set coercion PIN |

### GET /settings/emergency

**Response 200:**
```json
{
  "id": "uuid",
  "userId": "uuid",
  "countdownDurationSeconds": 5,
  "normalCancelMethod": "tap_pattern",
  "audioConsent": "none",
  "autoRecordAudio": false,
  "allowAiAnalysis": false,
  "shareAudioWithContacts": false,
  "audioContactIds": [],
  "audioShareThreshold": "critical",
  "enableTestMode": false,
  "triggerConfigurations": [],
  "emergencyMessage": "I need help. This is an emergency alert from SafeCircle."
}
```

Settings are auto-created on first access.

### PATCH /settings/emergency

**Request:** Any subset of the settings fields.

**Response 200:** Updated settings object.

### POST /settings/emergency/coercion-pin

**Request:**
```json
{
  "pin": "1234"
}
```

**Response:** 204 No Content. The PIN is hashed and never returned.

---

## Incidents

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/incidents` | Bearer | Create a new incident |
| GET | `/incidents` | Bearer | List incidents (paginated, filterable) |
| GET | `/incidents/:id` | Bearer | Get incident detail |
| POST | `/incidents/:id/activate` | Bearer | Activate after countdown |
| POST | `/incidents/:id/events` | Bearer | Add a timeline event |
| POST | `/incidents/:id/resolve` | Bearer | Resolve an incident |
| POST | `/incidents/:id/cancel` | Bearer | Cancel an incident |
| POST | `/incidents/:id/signal` | Bearer | Send a risk signal |

### POST /incidents

**Request:**
```json
{
  "triggerType": "manual_button",
  "isTestMode": false,
  "latitude": 48.8566,
  "longitude": 2.3522
}
```

**Response 201:** Incident object with `status: "countdown"`.

**Errors:** 400 Active incident already exists.

### GET /incidents

**Query parameters:** `page`, `limit`, `status`, `triggerType`, `isTestMode`, `from`, `to` (all optional).

**Response 200:**
```json
{
  "data": [ /* incident objects */ ],
  "total": 42,
  "page": 1,
  "limit": 20,
  "totalPages": 3
}
```

### POST /incidents/:id/activate

**Response 200:** Incident object with `status: "active"`.

### POST /incidents/:id/events

**Request:**
```json
{
  "type": "note_added",
  "payload": { "text": "User called back, seems safe" },
  "source": "operator"
}
```

**Response 201:** Event object.

### POST /incidents/:id/resolve

**Request:**
```json
{
  "reason": "User confirmed safety"
}
```

**Response 200:** Incident object with `status: "resolved"`.

### POST /incidents/:id/cancel

**Request:**
```json
{
  "isSecretCancel": false
}
```

If `isSecretCancel` is true, the incident appears cancelled to the user but remains active. See the Incident Lifecycle guide.

**Response 200:** Incident object.

### POST /incidents/:id/signal

**Request:**
```json
{
  "type": "audio_distress_detected",
  "payload": { "confidence": 0.87 }
}
```

**Response 200:** Updated risk assessment.

---

## Location

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/incidents/:id/location` | Bearer | Record a location update |
| GET | `/incidents/:id/locations` | Bearer | Get location trail |

### POST /incidents/:id/location

**Request:**
```json
{
  "latitude": 48.8566,
  "longitude": 2.3522,
  "accuracy": 10.5,
  "speed": 1.2,
  "heading": 180,
  "altitude": 35,
  "provider": "gps",
  "timestamp": "2026-04-06T12:00:00Z"
}
```

Only `latitude` and `longitude` are required.

**Response 201:** Location object.

### GET /incidents/:id/locations

**Query parameters:** `limit`, `since` (ISO timestamp, optional).

**Response 200:** Array of location objects.

---

## Audio

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/incidents/:id/audio` | Bearer | Upload audio chunk (multipart) |
| GET | `/incidents/:id/audio` | Bearer | List audio chunks |
| GET | `/incidents/:id/audio/:assetId/download` | Bearer | Get download URL |
| GET | `/incidents/:id/transcripts` | Bearer | List transcripts |

### POST /incidents/:id/audio

**Content-Type:** `multipart/form-data`

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `file` | File | Yes | Audio file (max 10 MB) |
| `duration` | Query param | Yes | Duration in seconds |

Allowed MIME types: `audio/webm`, `audio/ogg`, `audio/mp4`, `audio/mpeg`, `audio/wav`, `audio/x-wav`, `audio/aac`.

**Response 201:** Audio asset object with `transcriptionStatus: "pending"`.

### GET /incidents/:id/audio/:assetId/download

**Response 200:**
```json
{
  "url": "https://s3.example.com/presigned-url..."
}
```

---

## Timeline

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/incidents/:id/timeline` | Bearer | Get unified timeline |

### GET /incidents/:id/timeline

**Query parameters:** `includeInternal` (boolean, default false).

**Response 200:** Array of timeline entries sorted chronologically, including events, locations, and risk changes.

---

## Notifications / Contact Response

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| POST | `/incidents/:id/respond` | x-access-token | Record contact response |
| GET | `/incidents/:id/deliveries` | Bearer | List alert deliveries |
| GET | `/incidents/:id/responses` | Bearer | List contact responses |

### POST /incidents/:id/respond

**Headers:** `x-access-token: <contact_access_token>`

**Request:**
```json
{
  "responseType": "going_to_location",
  "note": "On my way, ETA 10 minutes"
}
```

Response types: `trying_to_reach`, `could_not_reach`, `going_to_location`, `calling_authorities`, `marked_reviewed`.

**Response 201:** Response object.

---

## Admin

All admin endpoints require the `admin` or `super_admin` role.

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/admin/incidents` | Admin | List all incidents (cross-user) |
| GET | `/admin/incidents/:id` | Admin | Full incident detail |
| GET | `/admin/incidents/:id/timeline` | Admin | Full incident timeline |
| GET | `/admin/incidents/:id/audio` | Admin | Incident audio + transcripts |
| GET | `/admin/audit-logs` | Admin | Search audit logs |
| GET | `/admin/feature-flags` | Admin | List all feature flags |
| PATCH | `/admin/feature-flags/:id` | Admin | Toggle a feature flag |
| GET | `/admin/health` | Admin | System health summary |
| GET | `/admin/stats` | Admin | Dashboard statistics |

### GET /admin/incidents

**Query parameters:** `status`, `risk_level`, `is_test_mode`, `start_date`, `end_date`, `user_id`, `page`, `limit`.

### PATCH /admin/feature-flags/:id

**Request:**
```json
{
  "enabled": true
}
```

**Response 200:** Updated feature flag object. An audit log entry is created.

### GET /admin/stats

**Response 200:**
```json
{
  "activeIncidents": 3,
  "totalUsers": 1250,
  "alertsToday": 47,
  "avgResponseTimeSeconds": 120
}
```

---

## WebSocket

The API exposes a WebSocket gateway at `/ws` (Socket.IO) for real-time updates during active incidents.

### Events (server to client)

| Event | Description |
|-------|-------------|
| `incident:updated` | Incident status or risk changed |
| `incident:location` | New location point |
| `incident:event` | New timeline event |
| `incident:audio` | Audio chunk uploaded |
| `incident:response` | Contact responded |

Clients join incident rooms by emitting `join:incident` with the incident ID after authentication.
