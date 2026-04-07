# SafeCircle — Device Test Checklist

Manual QA checklist for real-device testing. Each item should be tested on both Android and iOS where applicable.

## Prerequisites

- [ ] Backend running (`docker-compose up` or `npm run start:dev`)
- [ ] Database migrated and seeded (`npm run migration:run && npm run seed`)
- [ ] Mobile app installed on test device
- [ ] Device has working GPS and internet connection

### Environment Variables (for real alert delivery)

| Variable | Purpose | Required for |
|----------|---------|-------------|
| `TWILIO_ACCOUNT_SID` | Twilio account | SMS alerts |
| `TWILIO_AUTH_TOKEN` | Twilio auth | SMS alerts |
| `TWILIO_FROM_NUMBER` | Twilio sender | SMS alerts |
| `FIREBASE_PROJECT_ID` | FCM project | Push notifications |
| `FIREBASE_SERVICE_ACCOUNT_PATH` | FCM credentials | Push notifications |

Without these, alert delivery runs in **dry-run mode** (logged but not sent).

---

## 1. Onboarding

- [ ] Fresh install shows splash → login screen
- [ ] Register new account: name, email, phone, password
- [ ] After registration, onboarding flow starts
- [ ] **Permissions step:**
  - [ ] Tap "Allow" for Location → system permission dialog appears
  - [ ] Tap "Allow" for Notifications → system dialog appears
  - [ ] Tap "Allow" for Microphone → system dialog appears
  - [ ] Each permission shows green check after granted
  - [ ] "Continue anyway" works if permissions are skipped
  - [ ] Permanently denied permission shows message to open Settings
- [ ] **Add contact step:**
  - [ ] Enter name + phone → contact saved to backend
  - [ ] "Skip for now" works
- [ ] **Emergency message step:**
  - [ ] Message saved to backend settings
- [ ] **Completion** → navigates to dashboard

## 2. Login / Auth

- [ ] Login with registered credentials → dashboard
- [ ] Login with wrong password → error message
- [ ] App restart → auto-login (token refresh)
- [ ] Sign out from Settings → returns to login

## 3. Contacts Management

- [ ] View contacts list (loaded from backend, not mock data)
- [ ] Tap "Add contact" → form opens
- [ ] Fill required fields (name, phone) → save succeeds
- [ ] Missing name → validation error shown
- [ ] Edit existing contact → changes saved
- [ ] Delete contact → confirmation dialog → removed from list
- [ ] Reorder contacts (drag handle) → priority updated
- [ ] Contact permissions (SMS, push, voice, location, audio) → toggles work

## 4. Emergency Flow — Normal

- [ ] Long-press emergency button → incident created on backend
- [ ] Countdown starts (duration matches settings)
- [ ] Haptic feedback each second
- [ ] Stronger haptic in last 3 seconds
- [ ] Countdown completes → "Active" state shown
- [ ] Location status shows "Active"
- [ ] Audio status shows "Recording" (if consent enabled) or "Standby"
- [ ] Elapsed timer increments
- [ ] "End alert" → confirmation dialog → resolves incident
- [ ] Returns to dashboard, status bar shows "Safe"

## 5. Emergency Flow — Cancel

- [ ] During countdown, tap "Enter PIN to cancel"
- [ ] Enter a non-coercion PIN → incident cancelled → returns home
- [ ] During countdown, triple-tap top-right corner → secret cancel → returns home

## 6. Emergency Flow — Coercion

- [ ] Set coercion PIN in Settings → Coercion PIN screen
- [ ] Enter PIN + confirm → "Coercion PIN saved"
- [ ] Trigger emergency → countdown starts
- [ ] Enter coercion PIN → screen shows "Alert cancelled" (FAKE)
- [ ] **CRITICAL CHECK:** Verify in backend/admin that the incident is ESCALATED, not cancelled
- [ ] **CRITICAL CHECK:** Verify location tracking is still running on device
- [ ] Tap "Return to home" → dashboard appears normal
- [ ] Backend continues receiving location updates

## 7. Settings

- [ ] Emergency settings → countdown slider saves to backend
- [ ] Audio settings → toggle recording consent → saves
- [ ] Audio settings → toggle AI analysis → saves
- [ ] Privacy screen → audio toggle wired to backend
- [ ] Privacy screen → location sharing shows "always active" (locked)

## 8. Safe Journey

- [ ] Dashboard → tap "Journey" → journey screen opens
- [ ] Select duration (10/20/30/60 min)
- [ ] Tap "Start journey" → active journey screen
- [ ] Timer counts down
- [ ] "I arrived safely" → journey completed → returns home
- [ ] "I need more time" → adds 10 minutes
- [ ] "Cancel" → confirmation → cancels journey
- [ ] Timer expiry → backend creates incident (check admin dashboard)

## 9. Test Mode

- [ ] Toggle "Test mode" on dashboard
- [ ] Long-press emergency button → test mode screen
- [ ] Countdown → activation → same UI as real emergency
- [ ] End alert → dialog says "This was a test"
- [ ] **CRITICAL CHECK:** No real alerts sent to contacts (verify backend logs)

## 10. Connectivity

- [ ] Trigger emergency with good connection → works normally
- [ ] Put device in airplane mode during active alert → location queue builds
- [ ] Restore connection → queued locations sync (check backend logs)
- [ ] Trigger emergency with no connection → error message shown

## 11. Denied Permissions

- [ ] Deny location permission → emergency creation shows error/warning
- [ ] Deny microphone → audio recording shows "Standby" (not "Recording")
- [ ] Deny notifications → app still functions, but no local notifications

## 12. Background Behavior

- [ ] Start emergency → switch to another app → return to SafeCircle
- [ ] Check: is location still being sent? (verify backend logs)
- [ ] **Known limitation:** Without native foreground service, OS may kill the app
- [ ] Check: does the persistent notification appear? (Android only, requires native code)

## 13. Real-Time Updates (WebSocket)

- [ ] Start emergency on device A
- [ ] Open admin dashboard → verify incident appears
- [ ] Verify location updates stream to admin in real-time
- [ ] Verify timeline events appear

---

## Known Limitations (Not Bugs)

| Item | Status | Notes |
|------|--------|-------|
| Background audio recording | Foreground only | Requires native platform code |
| Background location (Android) | Limited | Needs native ForegroundService |
| Alarm siren sound | UI flash only | Needs native audio player |
| SMS fallback | Opens composer | User must tap Send |
| Data export | Not implemented | Button shows placeholder message |
| Data deletion | Logout only | Cascade delete endpoint needed |
| Push notification receipt | Not implemented | FCM delivery callback not wired |
| Forgot password | Not implemented | No backend endpoint |
