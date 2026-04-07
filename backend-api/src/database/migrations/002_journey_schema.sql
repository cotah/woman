-- Create journey status enum
CREATE TYPE journey_status AS ENUM ('active', 'completed', 'expired', 'escalated', 'cancelled');

-- Create journeys table
CREATE TABLE journeys (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status journey_status NOT NULL DEFAULT 'active',
  start_latitude DECIMAL(10, 7),
  start_longitude DECIMAL(10, 7),
  dest_latitude DECIMAL(10, 7) NOT NULL,
  dest_longitude DECIMAL(10, 7) NOT NULL,
  dest_label VARCHAR(255),
  arrival_radius_meters INT NOT NULL DEFAULT 200,
  duration_minutes INT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  last_checkin_at TIMESTAMPTZ,
  incident_id UUID REFERENCES incidents(id),
  is_test_mode BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_journeys_user_status ON journeys (user_id, status);
CREATE INDEX idx_journeys_expires_at ON journeys (expires_at) WHERE status = 'active';
