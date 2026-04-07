# Incident Lifecycle

This document describes the complete lifecycle of an incident in SafeCircle, from trigger activation through resolution.

---

## 1. Trigger Types

An incident can be created by any of the following triggers:

| Trigger | Enum | Phase | Description |
|---------|------|-------|-------------|
| Manual Button | `manual_button` | 1 | User presses the SOS button in the app |
| Coercion PIN | `coercion_pin` | 1 | User enters their coercion PIN instead of the normal cancel code |
| Physical Button | `physical_button` | 1 | Hardware button combination (e.g. power button x5) |
| Quick Shortcut | `quick_shortcut` | 1 | iOS Shortcut or Android Quick Tile |
| Wearable | `wearable` | 2 | Smartwatch trigger |
| Voice | `voice` | 2 | Voice-activated trigger |
| Geofence | `geofence` | 2 | Leaving a safe zone or entering a danger zone |
| Route Anomaly | `route_anomaly` | 2 | Significant deviation from an expected route |

---

## 2. Incident Status Flow

```
  trigger
    |
    v
 [pending] --> [countdown] --expires--> [active] --> [escalated]
    |              |                       |              |
    |              |cancel                 |resolve       |resolve
    v              v                       v              v
              [cancelled]              [resolved]     [resolved]
                                          |
                                     [false_alarm]
                                     [timed_out]
```

Status enum values: `pending`, `countdown`, `active`, `escalated`, `resolved`, `cancelled`, `false_alarm`, `timed_out`.

---

## 3. Countdown Phase

When an incident is created:

1. Status is set to `countdown`.
2. A `countdown_ends_at` timestamp is calculated from the user's `countdown_duration_seconds` setting (default: 5 seconds).
3. A `trigger_activated` event is written to the timeline.
4. A `countdown_started` event is written to the timeline.
5. The mobile app shows a full-screen countdown UI with a cancel option.

During this phase the user can:
- **Cancel normally** (tap pattern, button hold, etc.) -- incident moves to `cancelled`.
- **Enter coercion PIN** -- see Coercion Flow below.
- **Do nothing** -- countdown expires and the incident activates.

---

## 4. Active Phase

Once the countdown expires (or immediately for coercion triggers):

1. Status transitions to `active`.
2. An `incident_activated` event is written.
3. **Alert Wave 1** is dispatched to priority-1 contacts.
4. Location tracking begins (the mobile app sends location updates via `POST /incidents/:id/location`).
5. If audio recording is enabled in the user's settings, recording starts and chunks are uploaded via `POST /incidents/:id/audio`.
6. The risk engine begins processing signals.

---

## 5. Coercion Flow

When the coercion PIN is used as the trigger:

1. The incident is created with `is_coercion = true` and `trigger_type = coercion_pin`.
2. The risk score is immediately set to 95 (critical).
3. A `coercion_detected` event is written to the timeline.
4. The countdown is skipped -- the incident activates immediately.
5. The app UI shows a **fake cancellation screen** to the user, making it appear as though the alert was cancelled.
6. Behind the scenes, the incident remains active and alerts are dispatched silently.

---

## 6. Secret Cancellation

If the user is under duress and uses the normal cancel method:

1. The app sends `POST /incidents/:id/cancel` with `{ isSecretCancel: true }`.
2. The API writes a `secret_cancel` event to the timeline.
3. The incident **remains active** with status `escalated`.
4. The app displays a fake "cancelled" confirmation.
5. Alerts continue to be dispatched to contacts.

This ensures that even if an attacker forces the user to cancel, the emergency response continues.

---

## 7. Alert Waves

Alerts are dispatched in escalation waves based on contact priority:

| Wave | Timing | Contacts | Channels |
|------|--------|----------|----------|
| 1 | On activation | Priority 1 | SMS, Push |
| 2 | +2 minutes if no response | Priority 1-2 | SMS, Push, Voice Call |
| 3 | +5 minutes if no response | All contacts | SMS, Push, Voice Call |

Each alert delivery is tracked in the `alert_deliveries` table with statuses: `queued`, `sending`, `delivered`, `failed`, `retrying`.

Failed deliveries are retried up to 3 times with exponential backoff.

Alert messages include:
- The user's custom emergency message.
- A secure link to the contact web view (with a one-time access token).

---

## 8. Contact Responses

When a trusted contact receives an alert, they can click the secure link to access the contact web view. From there they can respond with one of:

| Response | Enum | Description |
|----------|------|-------------|
| Trying to Reach | `trying_to_reach` | Contact is attempting to call/message the user |
| Could Not Reach | `could_not_reach` | Contact tried but could not reach the user |
| Going to Location | `going_to_location` | Contact is heading to the user's location |
| Calling Authorities | `calling_authorities` | Contact is calling 911 or local emergency services |
| Marked Reviewed | `marked_reviewed` | Contact has seen the alert (admin/operator use) |

Each response is recorded in the `contact_responses` table and creates a `contact_responded` event on the timeline.

---

## 9. Risk Scoring

The risk engine continuously evaluates signals and adjusts the incident's risk score (0-100). The score maps to a risk level:

| Level | Score Range | Description |
|-------|-------------|-------------|
| `none` | 0-19 | No risk detected |
| `monitoring` | 20-39 | Low-level monitoring |
| `suspicious` | 40-69 | Suspicious activity detected |
| `alert` | 70-89 | High alert |
| `critical` | 90-100 | Critical -- maximum response |

### Risk Rules (Phase 1 -- Rule-Based)

| Rule | Signal Type | Score Delta | Once Per Incident | Description |
|------|-------------|-------------|-------------------|-------------|
| Manual Panic Trigger | `manual_panic_trigger` | +70 | Yes | User manually triggered panic |
| Coercion PIN Entered | `coercion_pin` | +95 | Yes | Coercion PIN used |
| Physical Button Trigger | `physical_trigger` | +70 | Yes | Hardware button activation |
| Countdown Not Cancelled | `countdown_not_cancelled` | +20 | Yes | Countdown expired naturally |
| Rapid Movement | `rapid_movement` | +10 | No | Unusual rapid movement (live only) |
| Audio Distress Detected | `audio_distress_detected` | +25 | No | AI detected distress in audio (live only) |
| Help Phrase Detected | `help_phrase_detected` | +35 | No | Voice transcription found distress phrase (live only) |
| Repeated Trigger | `repeated_trigger` | +10 | No | User triggered alert multiple times |

When the risk level changes, a `risk_score_changed` event is written to the timeline and an `incident_risk_assessments` record is created.

Phase 2 will introduce an ML-based risk engine that implements the same `RiskScoringStrategy` interface.

---

## 10. Resolution

An incident can be resolved in several ways:

| Resolution | Status | How |
|------------|--------|-----|
| User resolves | `resolved` | `POST /incidents/:id/resolve` with a reason |
| User cancels (during countdown) | `cancelled` | `POST /incidents/:id/cancel` |
| User marks false alarm | `false_alarm` | `POST /incidents/:id/resolve` with `{ reason: "false_alarm" }` |
| Timeout | `timed_out` | System auto-resolves after a configurable period |
| Admin/Operator resolves | `resolved` | Via admin API |

When resolved:
1. The status is updated and `resolved_at` is set.
2. An `incident_resolved` or `incident_timed_out` event is written.
3. All contact access tokens for the incident are revoked.
4. Audio recording stops.
5. Location tracking stops.

---

## 11. Timeline Events

Every significant action is recorded as an `incident_event` with a type, timestamp, payload, and source. Event types:

| Event Type | Description |
|------------|-------------|
| `trigger_activated` | Initial trigger was activated |
| `countdown_started` | Countdown timer began |
| `countdown_cancelled` | User cancelled during countdown |
| `incident_activated` | Incident transitioned to active |
| `coercion_detected` | Coercion PIN was used |
| `location_update` | New GPS location recorded |
| `audio_chunk_uploaded` | Audio chunk received |
| `transcription_completed` | Audio transcription finished |
| `risk_score_changed` | Risk score/level changed |
| `alert_dispatched` | Alert sent to a contact |
| `alert_delivered` | Alert delivery confirmed |
| `alert_failed` | Alert delivery failed |
| `contact_responded` | Contact submitted a response |
| `escalation_wave` | New escalation wave triggered |
| `incident_resolved` | Incident was resolved |
| `incident_timed_out` | Incident timed out |
| `secret_cancel` | Secret cancellation (coercion) |
| `ai_analysis_result` | AI analysis completed |
| `note_added` | Manual note added by admin/operator |
| `geofence_breach` | Geofence boundary crossed (Phase 2) |
| `route_deviation` | Route anomaly detected (Phase 2) |
| `wearable_signal` | Signal from wearable device (Phase 2) |
| `operator_action` | Human operator took action (Phase 2) |

Events with `is_internal = true` are only visible to admins and operators.
