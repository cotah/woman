// ── Auth ──
export interface AdminUser {
  id: string;
  email: string;
  name: string;
  role: 'super_admin' | 'admin' | 'operator' | 'viewer';
  createdAt: string;
}

export interface LoginRequest {
  email: string;
  password: string;
}

export interface LoginResponse {
  token: string;
  user: AdminUser;
}

// ── Incidents ──
// Aligned with shared-types/src/index.ts
export type IncidentStatus =
  | 'pending'
  | 'countdown'
  | 'active'
  | 'escalated'
  | 'resolved'
  | 'cancelled'
  | 'false_alarm'
  | 'timed_out';

export type RiskLevel =
  | 'none'
  | 'monitoring'
  | 'suspicious'
  | 'alert'
  | 'critical';

export type TriggerType =
  | 'manual_button'
  | 'coercion_pin'
  | 'physical_button'
  | 'quick_shortcut'
  | 'wearable'
  | 'voice'
  | 'geofence'
  | 'route_anomaly';

export interface Incident {
  id: string;
  userId: string;
  userName: string;
  userPhone: string;
  status: IncidentStatus;
  riskLevel: RiskLevel;
  triggerType: TriggerType;
  isTestMode: boolean;
  isCoercion: boolean;
  currentRiskScore: number;
  startedAt: string;
  resolvedAt: string | null;
  lastUpdatedAt: string;
  location: GeoPoint | null;
  contactsNotified: number;
  contactsResponded: number;
}

export interface IncidentDetail extends Incident {
  timeline: TimelineEvent[];
  audioAssets: AudioAsset[];
  alertLog: AlertDelivery[];
  contactResponses: ContactResponse[];
  locationTrail: GeoPoint[];
  resolution: Resolution | null;
}

export interface GeoPoint {
  latitude: number;
  longitude: number;
  accuracy: number;
  timestamp: string;
}

export interface TimelineEvent {
  id: string;
  type: string;
  title: string;
  description: string;
  timestamp: string;
  isInternal?: boolean;
  metadata?: Record<string, unknown>;
}

export interface AudioAsset {
  id: string;
  url: string;
  durationSeconds: number;
  recordedAt: string;
  transcript: string | null;
  transcriptStatus: 'pending' | 'processing' | 'completed' | 'failed';
}

export interface AlertDelivery {
  id: string;
  contactId: string;
  contactName: string;
  channel: 'sms' | 'push' | 'voice_call' | 'email';
  status: 'queued' | 'sending' | 'delivered' | 'failed' | 'retrying';
  wave: number;
  sentAt: string;
  deliveredAt: string | null;
  failureReason: string | null;
  retryCount: number;
}

export interface ContactResponse {
  contactId: string;
  contactName: string;
  response:
    | 'trying_to_reach'
    | 'could_not_reach'
    | 'going_to_location'
    | 'calling_authorities'
    | 'marked_reviewed';
  respondedAt: string;
  note: string | null;
}

export interface Resolution {
  resolvedBy: 'user' | 'contact' | 'admin' | 'system';
  resolvedByName: string;
  reason: string;
  isFalseAlarm: boolean;
  resolvedAt: string;
}

// ── Journey ──
export type JourneyStatus =
  | 'active'
  | 'completed'
  | 'expired'
  | 'escalated'
  | 'cancelled';

export interface Journey {
  id: string;
  userId: string;
  status: JourneyStatus;
  destLatitude: number;
  destLongitude: number;
  destLabel: string | null;
  durationMinutes: number;
  expiresAt: string;
  startedAt: string;
  completedAt: string | null;
  incidentId: string | null;
  isTestMode: boolean;
}

// ── Dashboard ──
export interface DashboardStats {
  activeIncidents: number;
  totalUsers: number;
  alertsSentToday: number;
  incidentsToday: number;
  systemHealth: SystemHealthStatus;
}

export interface SystemHealthStatus {
  overall: 'healthy' | 'degraded' | 'down';
  services: ServiceHealth[];
}

export interface ServiceHealth {
  name: string;
  status: 'healthy' | 'degraded' | 'down';
  latencyMs: number;
  lastChecked: string;
  message?: string;
}

// ── Audit Logs ──
export interface AuditLogEntry {
  id: string;
  action: string;
  actorId: string;
  actorName: string;
  actorRole: string;
  targetType: string;
  targetId: string;
  details: Record<string, unknown>;
  ipAddress: string;
  timestamp: string;
}

// ── Feature Flags ──
export type Phase = 'phase_1' | 'phase_2' | 'phase_3' | 'phase_4';

export interface FeatureFlag {
  id: string;
  key: string;
  name: string;
  description: string;
  enabled: boolean;
  phase: Phase;
  rolloutPercentage: number;
  updatedAt: string;
  updatedBy: string;
}

// ── Pagination ──
export interface PaginatedResponse<T> {
  data: T[];
  total: number;
  page: number;
  pageSize: number;
  totalPages: number;
}

export interface PaginationParams {
  page: number;
  pageSize: number;
}

// ── Filters ──
export interface IncidentFilters extends PaginationParams {
  status?: IncidentStatus;
  riskLevel?: RiskLevel;
  triggerType?: TriggerType;
  dateFrom?: string;
  dateTo?: string;
  testMode?: boolean;
  search?: string;
}

export interface AuditLogFilters extends PaginationParams {
  action?: string;
  actorId?: string;
  targetType?: string;
  dateFrom?: string;
  dateTo?: string;
  search?: string;
}
