/// All API endpoint constants matching the NestJS backend.
class ApiEndpoints {
  ApiEndpoints._();

  // ── Auth ──────────────────────────────────────
  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String logout = '/auth/logout';

  // ── Incidents ─────────────────────────────────
  static const String incidents = '/incidents';
  static String incident(String id) => '/incidents/$id';
  static String activateIncident(String id) => '/incidents/$id/activate';
  static String resolveIncident(String id) => '/incidents/$id/resolve';
  static String cancelIncident(String id) => '/incidents/$id/cancel';
  static String incidentSignal(String id) => '/incidents/$id/signal';
  static String incidentEvents(String id) => '/incidents/$id/events';

  // ── Incident Audio ────────────────────────────
  static String uploadAudio(String incidentId) =>
      '/incidents/$incidentId/audio';
  static String listAudioChunks(String incidentId) =>
      '/incidents/$incidentId/audio';
  static String downloadAudio(String incidentId, String assetId) =>
      '/incidents/$incidentId/audio/$assetId/download';
  static String incidentTranscripts(String incidentId) =>
      '/incidents/$incidentId/transcripts';

  // ── Incident Location ─────────────────────────
  static String incidentLocation(String incidentId) =>
      '/incidents/$incidentId/location';

  // ── Incident Timeline ─────────────────────────
  static String incidentTimeline(String incidentId) =>
      '/incidents/$incidentId/timeline';

  // ── Incident Notifications ────────────────────
  static String incidentRespond(String incidentId) =>
      '/incidents/$incidentId/respond';
  static String incidentDeliveries(String incidentId) =>
      '/incidents/$incidentId/deliveries';
  static String incidentResponses(String incidentId) =>
      '/incidents/$incidentId/responses';

  // ── Contacts ──────────────────────────────────
  static const String contacts = '/contacts';
  static String contact(String id) => '/contacts/$id';

  // ── Settings ──────────────────────────────────
  static const String emergencySettings = '/settings/emergency';
  static const String coercionPin = '/settings/emergency/coercion-pin';

  // ── Users / Profile ───────────────────────────
  static const String profile = '/users/me';
  static const String updateProfile = '/users/me';
  static const String registerDevice = '/users/me/devices';

  // ── Journey ──────────────────────────────────────
  static const String journey = '/journey';
  static const String journeyActive = '/journey/active';
  static String journeyCheckin(String id) => '/journey/$id/checkin';
  static String journeyComplete(String id) => '/journey/$id/complete';
  static String journeyLocation(String id) => '/journey/$id/location';
  static String journeyCancel(String id) => '/journey/$id';

  // ── Health / Diagnostics ───────────────────────
  static const String health = '/health';
  static const String pilotReadiness = '/health/pilot';
}
