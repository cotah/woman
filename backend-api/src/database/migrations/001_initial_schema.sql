-- ============================================================
-- SafeCircle Database Schema - Phase 1
-- ============================================================
-- This migration creates all Phase 1 tables and Phase 2 placeholders.
-- PostgreSQL 16+
-- ============================================================

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- ENUMS
-- ============================================================

CREATE TYPE user_role AS ENUM ('user', 'admin', 'super_admin', 'operator', 'org_admin');
CREATE TYPE device_platform AS ENUM ('ios', 'android', 'watch_os', 'wear_os');
CREATE TYPE incident_status AS ENUM ('pending', 'countdown', 'active', 'escalated', 'resolved', 'cancelled', 'false_alarm', 'timed_out');
CREATE TYPE trigger_type AS ENUM ('manual_button', 'coercion_pin', 'physical_button', 'quick_shortcut', 'wearable', 'voice', 'geofence', 'route_anomaly');
CREATE TYPE risk_level AS ENUM ('none', 'monitoring', 'suspicious', 'alert', 'critical');
CREATE TYPE incident_event_type AS ENUM (
  'trigger_activated', 'countdown_started', 'countdown_cancelled',
  'incident_activated', 'coercion_detected', 'location_update',
  'audio_chunk_uploaded', 'transcription_completed', 'risk_score_changed',
  'alert_dispatched', 'alert_delivered', 'alert_failed',
  'contact_responded', 'escalation_wave', 'incident_resolved',
  'incident_timed_out', 'secret_cancel', 'ai_analysis_result', 'note_added',
  'geofence_breach', 'route_deviation', 'wearable_signal', 'operator_action'
);
CREATE TYPE alert_channel AS ENUM ('push', 'sms', 'voice_call', 'email');
CREATE TYPE alert_delivery_status AS ENUM ('queued', 'sending', 'delivered', 'failed', 'retrying');
CREATE TYPE contact_response_type AS ENUM ('trying_to_reach', 'could_not_reach', 'going_to_location', 'calling_authorities', 'marked_reviewed');
CREATE TYPE audio_consent_level AS ENUM ('none', 'record_only', 'record_and_analyze', 'full');
CREATE TYPE transcription_status AS ENUM ('pending', 'processing', 'completed', 'failed');

-- ============================================================
-- USERS
-- ============================================================

CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email VARCHAR(255) NOT NULL UNIQUE,
  password_hash VARCHAR(255) NOT NULL,
  first_name VARCHAR(100) NOT NULL,
  last_name VARCHAR(100) NOT NULL,
  phone VARCHAR(20),
  role user_role NOT NULL DEFAULT 'user',
  is_active BOOLEAN NOT NULL DEFAULT true,
  onboarding_completed BOOLEAN NOT NULL DEFAULT false,
  email_verified BOOLEAN NOT NULL DEFAULT false,
  last_login_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_active ON users(is_active) WHERE deleted_at IS NULL;

-- ============================================================
-- USER DEVICES
-- ============================================================

CREATE TABLE user_devices (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform device_platform NOT NULL,
  device_token VARCHAR(500),
  push_token VARCHAR(500),
  device_model VARCHAR(100),
  os_version VARCHAR(50),
  app_version VARCHAR(50),
  is_active BOOLEAN NOT NULL DEFAULT true,
  last_seen_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_user_devices_user ON user_devices(user_id);
CREATE INDEX idx_user_devices_push ON user_devices(push_token) WHERE push_token IS NOT NULL;

-- ============================================================
-- TRUSTED CONTACTS
-- ============================================================

CREATE TABLE trusted_contacts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(200) NOT NULL,
  relationship VARCHAR(100),
  phone VARCHAR(20) NOT NULL,
  email VARCHAR(255),
  priority INTEGER NOT NULL DEFAULT 1,
  can_receive_sms BOOLEAN NOT NULL DEFAULT true,
  can_receive_push BOOLEAN NOT NULL DEFAULT false,
  can_receive_voice_call BOOLEAN NOT NULL DEFAULT false,
  can_access_audio BOOLEAN NOT NULL DEFAULT false,
  can_access_location BOOLEAN NOT NULL DEFAULT true,
  locale VARCHAR(10) NOT NULL DEFAULT 'en',
  is_verified BOOLEAN NOT NULL DEFAULT false,
  verification_token VARCHAR(100),
  verified_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_trusted_contacts_user ON trusted_contacts(user_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_trusted_contacts_priority ON trusted_contacts(user_id, priority);

-- ============================================================
-- EMERGENCY SETTINGS
-- ============================================================

CREATE TABLE emergency_settings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  countdown_duration_seconds INTEGER NOT NULL DEFAULT 5,
  coercion_pin_hash VARCHAR(255),
  normal_cancel_method VARCHAR(50) NOT NULL DEFAULT 'tap_pattern',
  audio_consent audio_consent_level NOT NULL DEFAULT 'none',
  auto_record_audio BOOLEAN NOT NULL DEFAULT false,
  allow_ai_analysis BOOLEAN NOT NULL DEFAULT false,
  share_audio_with_contacts BOOLEAN NOT NULL DEFAULT false,
  audio_contact_ids UUID[] DEFAULT '{}',
  audio_share_threshold risk_level NOT NULL DEFAULT 'critical',
  enable_test_mode BOOLEAN NOT NULL DEFAULT false,
  trigger_configurations JSONB NOT NULL DEFAULT '[]',
  emergency_message TEXT DEFAULT 'I need help. This is an emergency alert from SafeCircle.',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- INCIDENTS
-- ============================================================

CREATE TABLE incidents (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id),
  status incident_status NOT NULL DEFAULT 'pending',
  trigger_type trigger_type NOT NULL,
  is_coercion BOOLEAN NOT NULL DEFAULT false,
  is_test_mode BOOLEAN NOT NULL DEFAULT false,
  current_risk_score INTEGER NOT NULL DEFAULT 0,
  current_risk_level risk_level NOT NULL DEFAULT 'none',
  escalation_wave INTEGER NOT NULL DEFAULT 0,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  countdown_ends_at TIMESTAMPTZ,
  activated_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ,
  resolution_reason TEXT,
  last_location_at TIMESTAMPTZ,
  last_latitude DOUBLE PRECISION,
  last_longitude DOUBLE PRECISION,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_incidents_user ON incidents(user_id);
CREATE INDEX idx_incidents_status ON incidents(status);
CREATE INDEX idx_incidents_active ON incidents(user_id, status) WHERE status IN ('pending', 'countdown', 'active', 'escalated');
CREATE INDEX idx_incidents_created ON incidents(created_at DESC);
CREATE INDEX idx_incidents_test ON incidents(is_test_mode);

-- ============================================================
-- INCIDENT EVENTS (append-only timeline)
-- ============================================================

CREATE TABLE incident_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  incident_id UUID NOT NULL REFERENCES incidents(id),
  type incident_event_type NOT NULL,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  payload JSONB NOT NULL DEFAULT '{}',
  source VARCHAR(100) NOT NULL DEFAULT 'system',
  is_internal BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_incident_events_incident ON incident_events(incident_id, timestamp);
CREATE INDEX idx_incident_events_type ON incident_events(incident_id, type);

-- ============================================================
-- INCIDENT LOCATIONS
-- ============================================================

CREATE TABLE incident_locations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  incident_id UUID NOT NULL REFERENCES incidents(id),
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  accuracy DOUBLE PRECISION,
  speed DOUBLE PRECISION,
  heading DOUBLE PRECISION,
  altitude DOUBLE PRECISION,
  provider VARCHAR(50),
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_incident_locations_incident ON incident_locations(incident_id, timestamp);

-- ============================================================
-- AUDIO ASSETS
-- ============================================================

CREATE TABLE incident_audio_assets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  incident_id UUID NOT NULL REFERENCES incidents(id),
  chunk_index INTEGER NOT NULL,
  duration_seconds DOUBLE PRECISION NOT NULL,
  storage_key VARCHAR(500) NOT NULL,
  mime_type VARCHAR(50) NOT NULL DEFAULT 'audio/webm',
  size_bytes BIGINT NOT NULL,
  transcription_status transcription_status NOT NULL DEFAULT 'pending',
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audio_assets_incident ON incident_audio_assets(incident_id, chunk_index);

-- ============================================================
-- TRANSCRIPTS
-- ============================================================

CREATE TABLE incident_transcripts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  audio_asset_id UUID NOT NULL REFERENCES incident_audio_assets(id),
  incident_id UUID NOT NULL REFERENCES incidents(id),
  text TEXT NOT NULL,
  confidence DOUBLE PRECISION NOT NULL DEFAULT 0,
  language VARCHAR(10) NOT NULL DEFAULT 'en',
  distress_signals JSONB NOT NULL DEFAULT '[]',
  ai_summary TEXT,
  ai_risk_indicators JSONB DEFAULT '[]',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_transcripts_incident ON incident_transcripts(incident_id);
CREATE INDEX idx_transcripts_audio ON incident_transcripts(audio_asset_id);

-- ============================================================
-- RISK ASSESSMENTS
-- ============================================================

CREATE TABLE incident_risk_assessments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  incident_id UUID NOT NULL REFERENCES incidents(id),
  previous_score INTEGER NOT NULL,
  new_score INTEGER NOT NULL,
  previous_level risk_level NOT NULL,
  new_level risk_level NOT NULL,
  rule_id VARCHAR(100) NOT NULL,
  rule_name VARCHAR(200) NOT NULL,
  reason TEXT NOT NULL,
  signal_type VARCHAR(100) NOT NULL,
  signal_payload JSONB DEFAULT '{}',
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_risk_assessments_incident ON incident_risk_assessments(incident_id, timestamp);

-- ============================================================
-- ALERT DELIVERIES
-- ============================================================

CREATE TABLE alert_deliveries (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  incident_id UUID NOT NULL REFERENCES incidents(id),
  contact_id UUID NOT NULL REFERENCES trusted_contacts(id),
  channel alert_channel NOT NULL,
  status alert_delivery_status NOT NULL DEFAULT 'queued',
  wave INTEGER NOT NULL DEFAULT 1,
  message_body TEXT,
  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  failure_reason TEXT,
  retry_count INTEGER NOT NULL DEFAULT 0,
  max_retries INTEGER NOT NULL DEFAULT 3,
  external_id VARCHAR(200),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_alert_deliveries_incident ON alert_deliveries(incident_id);
CREATE INDEX idx_alert_deliveries_contact ON alert_deliveries(contact_id);
CREATE INDEX idx_alert_deliveries_status ON alert_deliveries(status) WHERE status IN ('queued', 'sending', 'retrying');

-- ============================================================
-- CONTACT RESPONSES
-- ============================================================

CREATE TABLE contact_responses (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  incident_id UUID NOT NULL REFERENCES incidents(id),
  contact_id UUID NOT NULL REFERENCES trusted_contacts(id),
  response_type contact_response_type NOT NULL,
  note TEXT,
  responded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_contact_responses_incident ON contact_responses(incident_id);

-- ============================================================
-- AUDIT LOGS (append-only)
-- ============================================================

CREATE TABLE audit_logs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES users(id),
  action VARCHAR(100) NOT NULL,
  resource VARCHAR(100) NOT NULL,
  resource_id UUID,
  details JSONB NOT NULL DEFAULT '{}',
  ip_address INET,
  user_agent TEXT,
  timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_user ON audit_logs(user_id, timestamp DESC);
CREATE INDEX idx_audit_logs_resource ON audit_logs(resource, resource_id);
CREATE INDEX idx_audit_logs_action ON audit_logs(action, timestamp DESC);
CREATE INDEX idx_audit_logs_timestamp ON audit_logs(timestamp DESC);

-- ============================================================
-- FEATURE FLAGS
-- ============================================================

CREATE TABLE feature_flags (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  key VARCHAR(100) NOT NULL UNIQUE,
  name VARCHAR(200) NOT NULL,
  description TEXT,
  enabled BOOLEAN NOT NULL DEFAULT false,
  phase INTEGER NOT NULL DEFAULT 1,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SESSIONS
-- ============================================================

CREATE TABLE user_sessions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  refresh_token_hash VARCHAR(255) NOT NULL,
  device_id UUID REFERENCES user_devices(id),
  ip_address INET,
  user_agent TEXT,
  expires_at TIMESTAMPTZ NOT NULL,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sessions_user ON user_sessions(user_id) WHERE revoked_at IS NULL;
CREATE INDEX idx_sessions_token ON user_sessions(refresh_token_hash);

-- ============================================================
-- CONTACT ACCESS TOKENS (for secure web view)
-- ============================================================

CREATE TABLE contact_access_tokens (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  incident_id UUID NOT NULL REFERENCES incidents(id),
  contact_id UUID NOT NULL REFERENCES trusted_contacts(id),
  token_hash VARCHAR(255) NOT NULL UNIQUE,
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_contact_tokens_hash ON contact_access_tokens(token_hash);
CREATE INDEX idx_contact_tokens_incident ON contact_access_tokens(incident_id);

-- ============================================================
-- PHASE 2 PLACEHOLDER TABLES
-- ============================================================

-- Geofences (Phase 2)
CREATE TABLE geofences (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name VARCHAR(200) NOT NULL,
  type VARCHAR(20) NOT NULL DEFAULT 'safe_zone',
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  radius_meters DOUBLE PRECISION NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Wearable devices (Phase 2)
CREATE TABLE wearable_devices (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform device_platform NOT NULL,
  device_identifier VARCHAR(255) NOT NULL,
  device_token VARCHAR(500),
  is_active BOOLEAN NOT NULL DEFAULT false,
  last_sync_at TIMESTAMPTZ,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Organizations (Phase 2)
CREATE TABLE organizations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name VARCHAR(255) NOT NULL,
  type VARCHAR(50) NOT NULL DEFAULT 'community',
  is_active BOOLEAN NOT NULL DEFAULT true,
  settings JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Organization membership (Phase 2)
CREATE TABLE organization_members (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role VARCHAR(50) NOT NULL DEFAULT 'member',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(organization_id, user_id)
);

-- Subscriptions (Phase 2)
CREATE TABLE subscriptions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id),
  plan_id VARCHAR(100) NOT NULL,
  status VARCHAR(50) NOT NULL DEFAULT 'active',
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- AI Model Runs (Phase 2)
CREATE TABLE ai_model_runs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  incident_id UUID REFERENCES incidents(id),
  model_type VARCHAR(100) NOT NULL,
  model_version VARCHAR(50),
  input_payload JSONB NOT NULL DEFAULT '{}',
  output_payload JSONB NOT NULL DEFAULT '{}',
  confidence DOUBLE PRECISION,
  processing_time_ms INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Route anomaly events (Phase 2)
CREATE TABLE route_anomaly_events (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id),
  incident_id UUID REFERENCES incidents(id),
  expected_route JSONB,
  actual_position JSONB NOT NULL,
  deviation_meters DOUBLE PRECISION,
  anomaly_type VARCHAR(50),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SEED FEATURE FLAGS
-- ============================================================

INSERT INTO feature_flags (key, name, description, enabled, phase) VALUES
  ('audio_recording', 'Audio Recording', 'Enable audio recording during incidents', true, 1),
  ('audio_ai_analysis', 'Audio AI Analysis', 'Enable AI-powered audio analysis', true, 1),
  ('sms_alerts', 'SMS Alerts', 'Enable SMS alert delivery', true, 1),
  ('push_alerts', 'Push Notifications', 'Enable push notification alerts', true, 1),
  ('voice_call_alerts', 'Voice Call Alerts', 'Enable voice call alert delivery', true, 1),
  ('coercion_mode', 'Coercion Mode', 'Enable coercion PIN functionality', true, 1),
  ('test_mode', 'Test Mode', 'Enable incident simulation mode', true, 1),
  ('wearable_triggers', 'Wearable Triggers', 'Enable smartwatch trigger support', false, 2),
  ('disguised_interface', 'Disguised Interface', 'Enable fake calculator / disguised app mode', false, 2),
  ('ai_risk_engine', 'AI Risk Engine', 'Enable ML-based risk scoring', false, 2),
  ('geofencing', 'Geofencing', 'Enable geofence-based alerts', false, 2),
  ('route_anomaly', 'Route Anomaly Detection', 'Enable route deviation detection', false, 2),
  ('org_mode', 'Organization Mode', 'Enable campus/enterprise features', false, 2),
  ('human_operators', 'Human Operators', 'Enable human-assisted response center', false, 2),
  ('silent_challenge', 'Silent Challenge-Response', 'Enable silent safety check flows', false, 2),
  ('evidence_export', 'Evidence Package Export', 'Enable incident evidence export', false, 2);

-- ============================================================
-- UPDATED_AT TRIGGER FUNCTION
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply to all tables with updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_user_devices_updated_at BEFORE UPDATE ON user_devices FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_trusted_contacts_updated_at BEFORE UPDATE ON trusted_contacts FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_emergency_settings_updated_at BEFORE UPDATE ON emergency_settings FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_incidents_updated_at BEFORE UPDATE ON incidents FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_alert_deliveries_updated_at BEFORE UPDATE ON alert_deliveries FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_feature_flags_updated_at BEFORE UPDATE ON feature_flags FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
