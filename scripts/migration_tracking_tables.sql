-- ============================================================
-- SafeCircle: Location Tracking & Learned Places Tables
-- Run this in Railway Postgres (Query tab)
-- ============================================================

-- Table: location_snapshots
-- Stores continuous location data from always-on 24/7 tracking
CREATE TABLE IF NOT EXISTS location_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy DOUBLE PRECISION,
    "timestamp" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_location_snapshots_user_timestamp
    ON location_snapshots (user_id, "timestamp" DESC);

CREATE INDEX IF NOT EXISTS idx_location_snapshots_user_coords
    ON location_snapshots (user_id, latitude, longitude);

CREATE INDEX IF NOT EXISTS idx_location_snapshots_user_id
    ON location_snapshots (user_id);

-- Table: learned_places
-- AI-learned frequent places for safety analysis
CREATE TABLE IF NOT EXISTS learned_places (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    label VARCHAR(100),
    auto_label VARCHAR(50),
    visit_count INT NOT NULL DEFAULT 0,
    is_confirmed_safe BOOLEAN NOT NULL DEFAULT FALSE,
    is_flagged BOOLEAN NOT NULL DEFAULT FALSE,
    flag_reason TEXT,
    first_visited TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_visited TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    hour_distribution JSONB,
    weekday_distribution JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_learned_places_user_id
    ON learned_places (user_id);

-- Verify tables were created
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
AND table_name IN ('location_snapshots', 'learned_places');
