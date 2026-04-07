// SafeCircle Shared Types
// These types are shared between backend, admin-web, and contact-web

// ============================================================
// ENUMS
// ============================================================

export enum IncidentStatus {
  PENDING = 'pending',
  COUNTDOWN = 'countdown',
  ACTIVE = 'active',
  ESCALATED = 'escalated',
  RESOLVED = 'resolved',
  CANCELLED = 'cancelled',
  FALSE_ALARM = 'false_alarm',
  TIMED_OUT = 'timed_out',
}

export enum TriggerType {
  MANUAL_BUTTON = 'manual_button',
  COERCION_PIN = 'coercion_pin',
  PHYSICAL_BUTTON = 'physical_button',
  QUICK_SHORTCUT = 'quick_shortcut',
  // Phase 2
  WEARABLE = 'wearable',
  VOICE = 'voice',
  GEOFENCE = 'geofence',
  ROUTE_ANOMALY = 'route_anomaly',
}

export enum RiskLevel {
  NONE = 'none',
  MONITORING = 'monitoring',
  SUSPICIOUS = 'suspicious',
  ALERT = 'alert',
  CRITICAL = 'critical',
}

export enum IncidentEventType {
  TRIGGER_ACTIVATED = 'trigger_activated',
  COUNTDOWN_STARTED = 'countdown_started',
  COUNTDOWN_CANCELLED = 'countdown_cancelled',
  INCIDENT_ACTIVATED = 'incident_activated',
  COERCION_DETECTED = 'coercion_detected',
  LOCATION_UPDATE = 'location_update',
  AUDIO_CHUNK_UPLOADED = 'audio_chunk_uploaded',
  TRANSCRIPTION_COMPLETED = 'transcription_completed',
  RISK_SCORE_CHANGED = 'risk_score_changed',
  ALERT_DISPATCHED = 'alert_dispatched',
  ALERT_DELIVERED = 'alert_delivered',
  ALERT_FAILED = 'alert_failed',
  CONTACT_RESPONDED = 'contact_responded',
  ESCALATION_WAVE = 'escalation_wave',
  INCIDENT_RESOLVED = 'incident_resolved',
  INCIDENT_TIMED_OUT = 'incident_timed_out',
  SECRET_CANCEL = 'secret_cancel',
  AI_ANALYSIS_RESULT = 'ai_analysis_result',
  NOTE_ADDED = 'note_added',
  // Phase 2
  GEOFENCE_BREACH = 'geofence_breach',
  ROUTE_DEVIATION = 'route_deviation',
  WEARABLE_SIGNAL = 'wearable_signal',
  OPERATOR_ACTION = 'operator_action',
}

export enum AlertChannel {
  PUSH = 'push',
  SMS = 'sms',
  VOICE_CALL = 'voice_call',
  EMAIL = 'email',
}

export enum AlertDeliveryStatus {
  QUEUED = 'queued',
  SENDING = 'sending',
  DELIVERED = 'delivered',
  FAILED = 'failed',
  RETRYING = 'retrying',
}

export enum ContactResponseType {
  TRYING_TO_REACH = 'trying_to_reach',
  COULD_NOT_REACH = 'could_not_reach',
  GOING_TO_LOCATION = 'going_to_location',
  CALLING_AUTHORITIES = 'calling_authorities',
  MARKED_REVIEWED = 'marked_reviewed',
}

export enum UserRole {
  USER = 'user',
  ADMIN = 'admin',
  SUPER_ADMIN = 'super_admin',
  // Phase 2
  OPERATOR = 'operator',
  ORG_ADMIN = 'org_admin',
}

export enum AudioConsentLevel {
  NONE = 'none',
  RECORD_ONLY = 'record_only',
  RECORD_AND_ANALYZE = 'record_and_analyze',
  FULL = 'full',
}

export enum DevicePlatform {
  IOS = 'ios',
  ANDROID = 'android',
  // Phase 2
  WATCH_OS = 'watch_os',
  WEAR_OS = 'wear_os',
}

// ============================================================
// INTERFACES
// ============================================================

export interface UserProfile {
  id: string;
  email: string;
  firstName: string;
  lastName: string;
  phone?: string;
  role: UserRole;
  isActive: boolean;
  onboardingCompleted: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface TrustedContact {
  id: string;
  userId: string;
  name: string;
  relationship?: string;
  phone: string;
  email?: string;
  priority: number;
  canReceiveSms: boolean;
  canReceivePush: boolean;
  canReceiveVoiceCall: boolean;
  canAccessAudio: boolean;
  canAccessLocation: boolean;
  locale: string;
  isVerified: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface EmergencySettings {
  id: string;
  userId: string;
  countdownDurationSeconds: number;
  coercionPinHash?: string;
  hasCoercionPin: boolean;
  normalCancelMethod: string;
  audioConsent: AudioConsentLevel;
  autoRecordAudio: boolean;
  allowAiAnalysis: boolean;
  shareAudioWithContacts: boolean;
  audioContactIds: string[];
  audioShareThreshold: RiskLevel;
  enableTestMode: boolean;
  triggerConfigurations: TriggerConfiguration[];
  createdAt: string;
  updatedAt: string;
}

export interface TriggerConfiguration {
  type: TriggerType;
  enabled: boolean;
  config: Record<string, unknown>;
}

export interface Incident {
  id: string;
  userId: string;
  status: IncidentStatus;
  triggerType: TriggerType;
  isCoercion: boolean;
  isTestMode: boolean;
  currentRiskScore: number;
  currentRiskLevel: RiskLevel;
  startedAt: string;
  activatedAt?: string;
  resolvedAt?: string;
  resolutionReason?: string;
  createdAt: string;
  updatedAt: string;
}

export interface IncidentEvent {
  id: string;
  incidentId: string;
  type: IncidentEventType;
  timestamp: string;
  payload: Record<string, unknown>;
  source: string;
  isInternal: boolean;
}

export interface IncidentLocation {
  id: string;
  incidentId: string;
  latitude: number;
  longitude: number;
  accuracy?: number;
  speed?: number;
  heading?: number;
  altitude?: number;
  provider?: string;
  timestamp: string;
}

export interface AudioAsset {
  id: string;
  incidentId: string;
  chunkIndex: number;
  durationSeconds: number;
  storageKey: string;
  mimeType: string;
  sizeBytes: number;
  uploadedAt: string;
  transcriptionStatus: 'pending' | 'processing' | 'completed' | 'failed';
}

export interface Transcript {
  id: string;
  audioAssetId: string;
  incidentId: string;
  text: string;
  confidence: number;
  language: string;
  distressSignals: DistressSignal[];
  createdAt: string;
}

export interface DistressSignal {
  type: string;
  confidence: number;
  timestamp: number;
  description: string;
}

export interface AlertDelivery {
  id: string;
  incidentId: string;
  contactId: string;
  channel: AlertChannel;
  status: AlertDeliveryStatus;
  wave: number;
  sentAt?: string;
  deliveredAt?: string;
  failedAt?: string;
  failureReason?: string;
  retryCount: number;
  externalId?: string;
}

export interface ContactResponse {
  id: string;
  incidentId: string;
  contactId: string;
  responseType: ContactResponseType;
  note?: string;
  respondedAt: string;
}

export interface RiskAssessment {
  id: string;
  incidentId: string;
  previousScore: number;
  newScore: number;
  previousLevel: RiskLevel;
  newLevel: RiskLevel;
  rule: string;
  reason: string;
  signalType: string;
  timestamp: string;
}

export interface AuditLogEntry {
  id: string;
  userId?: string;
  action: string;
  resource: string;
  resourceId?: string;
  details: Record<string, unknown>;
  ipAddress?: string;
  userAgent?: string;
  timestamp: string;
}

export interface FeatureFlag {
  id: string;
  key: string;
  name: string;
  description: string;
  enabled: boolean;
  phase: number;
  metadata: Record<string, unknown>;
}

// ============================================================
// API DTOs
// ============================================================

export interface RegisterDto {
  email: string;
  password: string;
  firstName: string;
  lastName: string;
  phone?: string;
}

export interface LoginDto {
  email: string;
  password: string;
}

export interface AuthResponse {
  accessToken: string;
  refreshToken: string;
  user: UserProfile;
}

export interface CreateContactDto {
  name: string;
  relationship?: string;
  phone: string;
  email?: string;
  priority: number;
  canReceiveSms: boolean;
  canReceivePush: boolean;
  canReceiveVoiceCall: boolean;
  canAccessAudio: boolean;
  canAccessLocation: boolean;
  locale?: string;
}

export interface UpdateContactDto extends Partial<CreateContactDto> {}

export interface UpdateEmergencySettingsDto {
  countdownDurationSeconds?: number;
  coercionPin?: string;
  normalCancelMethod?: string;
  audioConsent?: AudioConsentLevel;
  autoRecordAudio?: boolean;
  allowAiAnalysis?: boolean;
  shareAudioWithContacts?: boolean;
  audioContactIds?: string[];
  audioShareThreshold?: RiskLevel;
  enableTestMode?: boolean;
  triggerConfigurations?: TriggerConfiguration[];
}

export interface CreateIncidentDto {
  triggerType: TriggerType;
  isCoercion: boolean;
  isTestMode: boolean;
  initialLatitude?: number;
  initialLongitude?: number;
}

export interface LocationUpdateDto {
  latitude: number;
  longitude: number;
  accuracy?: number;
  speed?: number;
  heading?: number;
  altitude?: number;
  provider?: string;
  timestamp: string;
}

export interface AudioUploadMeta {
  chunkIndex: number;
  durationSeconds: number;
  mimeType: string;
}

export interface ResolveIncidentDto {
  reason: string;
}

export interface ContactRespondDto {
  responseType: ContactResponseType;
  note?: string;
}

// ============================================================
// WEBSOCKET EVENTS
// ============================================================

export enum WsEventType {
  INCIDENT_UPDATE = 'incident:update',
  LOCATION_UPDATE = 'location:update',
  RISK_UPDATE = 'risk:update',
  ALERT_UPDATE = 'alert:update',
  CONTACT_RESPONSE = 'contact:response',
  TRANSCRIPT_READY = 'transcript:ready',
  TIMELINE_EVENT = 'timeline:event',
}

export interface WsMessage<T = unknown> {
  event: WsEventType;
  data: T;
  timestamp: string;
}

// ============================================================
// RISK ENGINE TYPES
// ============================================================

export interface RiskRule {
  id: string;
  signalType: string;
  scoreDelta: number;
  condition?: Record<string, unknown>;
  reason: string;
  enabled: boolean;
}

export interface RiskEvaluation {
  previousScore: number;
  newScore: number;
  previousLevel: RiskLevel;
  newLevel: RiskLevel;
  appliedRules: AppliedRule[];
}

export interface AppliedRule {
  ruleId: string;
  signalType: string;
  scoreDelta: number;
  reason: string;
}

// ============================================================
// PHASE 2 PLACEHOLDER TYPES
// ============================================================

export interface Geofence {
  id: string;
  userId: string;
  name: string;
  type: 'safe_zone' | 'danger_zone';
  latitude: number;
  longitude: number;
  radiusMeters: number;
  isActive: boolean;
}

export interface WearableDevice {
  id: string;
  userId: string;
  platform: 'watch_os' | 'wear_os';
  deviceToken: string;
  isActive: boolean;
}

export interface Organization {
  id: string;
  name: string;
  type: 'campus' | 'enterprise' | 'community';
  isActive: boolean;
}

// ============================================================
// JOURNEY (Safe Journey / "Cheguei Bem")
// ============================================================

export enum JourneyStatus {
  ACTIVE = 'active',
  COMPLETED = 'completed',
  EXPIRED = 'expired',
  ESCALATED = 'escalated',
  CANCELLED = 'cancelled',
}

export interface Journey {
  id: string;
  userId: string;
  status: JourneyStatus;
  startLatitude: number | null;
  startLongitude: number | null;
  destLatitude: number;
  destLongitude: number;
  destLabel: string | null;
  arrivalRadiusMeters: number;
  durationMinutes: number;
  expiresAt: string;
  startedAt: string;
  completedAt: string | null;
  lastCheckinAt: string | null;
  incidentId: string | null;
  isTestMode: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface CreateJourneyDto {
  destLatitude: number;
  destLongitude: number;
  destLabel?: string;
  durationMinutes: number;
  arrivalRadiusMeters?: number;
  startLatitude?: number;
  startLongitude?: number;
  isTestMode?: boolean;
}

export interface ExtendJourneyDto {
  additionalMinutes: number;
}

export interface JourneyLocationDto {
  latitude: number;
  longitude: number;
  accuracy?: number;
}
