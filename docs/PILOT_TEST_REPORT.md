# SafeCircle — Pilot Test Report

**Tester:**  
**Date:**  
**Device:** (model, OS version)  
**App version:**  
**Backend environment:** (dev / staging / production)  
**Alert delivery mode:** (DRY-RUN / LIVE — check System Readiness screen)

---

## Test Scenarios

### 1. Emergency Flow — Normal

| Field | Value |
|-------|-------|
| **Scenario** | Long-press SOS → countdown → activate → resolve |
| **Expected** | Incident created, contacts notified, location streaming, clean resolve |
| **Actual result** | |
| **Time from trigger to incident created** | ___s |
| **Time from activation to first contact alert** | ___s |
| **Time from activation to location visible in admin** | ___s |
| **User confusion points** | |
| **Failures** | |
| **Severity** | None / Low / Medium / High / Critical |

---

### 2. Emergency Flow — Coercion

| Field | Value |
|-------|-------|
| **Scenario** | Trigger → enter coercion PIN → verify fake cancel + backend escalation |
| **Expected** | UI shows "cancelled", backend shows ESCALATED, location keeps streaming |
| **Actual result** | |
| **Did UI show fake cancel?** | Yes / No |
| **Did backend escalate? (check admin)** | Yes / No |
| **Did location continue streaming?** | Yes / No |
| **User confusion points** | |
| **Failures** | |
| **Severity** | None / Low / Medium / High / Critical |

---

### 3. Emergency Flow — Cancel

| Field | Value |
|-------|-------|
| **Scenario** | Trigger → triple-tap cancel OR PIN cancel |
| **Expected** | Incident cancelled, returns to home, tracking stops |
| **Actual result** | |
| **User confusion points** | |
| **Failures** | |
| **Severity** | None / Low / Medium / High / Critical |

---

### 4. Safe Journey

| Field | Value |
|-------|-------|
| **Scenario** | Start journey → track → complete (or let timer expire) |
| **Expected** | Journey created, location tracked, completion/expiry handled |
| **Actual result** | |
| **Time from start to location visible** | ___s |
| **Did auto-complete on arrival work?** | Yes / No / N/A |
| **Did timer expiry trigger incident?** | Yes / No / N/A |
| **User confusion points** | |
| **Failures** | |
| **Severity** | None / Low / Medium / High / Critical |

---

### 5. Contact Management

| Field | Value |
|-------|-------|
| **Scenario** | Add / edit / delete / reorder contacts |
| **Expected** | All CRUD operations work, data persists |
| **Actual result** | |
| **User confusion points** | |
| **Failures** | |
| **Severity** | None / Low / Medium / High / Critical |

---

### 6. Test Mode

| Field | Value |
|-------|-------|
| **Scenario** | Toggle test mode → trigger → full flow → verify no real alerts |
| **Expected** | Same UI flow, no real alerts sent, clear "this was a test" message |
| **Actual result** | |
| **Were real alerts sent? (check backend logs)** | Yes / No |
| **User confusion points** | |
| **Failures** | |
| **Severity** | None / Low / Medium / High / Critical |

---

### 7. Onboarding

| Field | Value |
|-------|-------|
| **Scenario** | Fresh install → register → onboarding → permissions → add contact |
| **Expected** | Smooth flow, real permissions requested, contact saved |
| **Actual result** | |
| **Permissions dialog appeared?** | Location: Y/N, Mic: Y/N, Notif: Y/N |
| **Contact saved to backend?** | Yes / No |
| **User confusion points** | |
| **Failures** | |
| **Severity** | None / Low / Medium / High / Critical |

---

### 8. Background Behavior

| Field | Value |
|-------|-------|
| **Scenario** | Start alert → minimize app → wait 2 min → check backend |
| **Expected** | Location continues (or degrades gracefully) |
| **Actual result** | |
| **Did location continue?** | Yes / No / Partial |
| **Was app killed by OS?** | Yes / No |
| **System Readiness shows background native?** | Yes / No |
| **User confusion points** | |
| **Failures** | |
| **Severity** | None / Low / Medium / High / Critical |

---

### 9. System Readiness Screen

| Field | Value |
|-------|-------|
| **Scenario** | Open Settings → System Readiness |
| **All permissions shown correctly?** | Yes / No |
| **Provider modes shown (DRY-RUN/LIVE)?** | Yes / No |
| **WebSocket status accurate?** | Yes / No |
| **Contact count accurate?** | Yes / No |
| **Failures** | |

---

## Summary

| Category | Pass / Fail | Notes |
|----------|------------|-------|
| Emergency normal | | |
| Emergency coercion | | |
| Emergency cancel | | |
| Safe journey | | |
| Contacts | | |
| Test mode | | |
| Onboarding | | |
| Background | | |
| System readiness | | |

## Overall Assessment

**Ready for wider testing?** Yes / No / With caveats

**Top issues to fix before next round:**
1. 
2. 
3. 

**User feedback / quotes:**
- 
- 
