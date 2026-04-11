-- Migration: Add AI learning and safety check-in fields to journeys
-- These fields enable smart duration estimation and safety check-in before escalation.

ALTER TABLE journeys
  ADD COLUMN IF NOT EXISTS ai_estimated_minutes INT DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS checkin_sent BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS checkin_response VARCHAR(10) DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS checkin_sent_at TIMESTAMPTZ DEFAULT NULL;
