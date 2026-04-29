-- Migration: Prevent duplicate transcripts on BullMQ retry
--
-- After Fix 4 (1e899bd, 2026-04-28), processTranscription
-- persists a transcript and then runs side effects (events,
-- risk signals, broadcast). If the method throws AFTER
-- transcriptRepo.save, BullMQ retries the same job and
-- re-creates everything, including a duplicate transcript row.
--
-- Each audio chunk = exactly 1 transcript = natural invariant.
-- This UNIQUE constraint enforces it at the DB level. The
-- service layer also pre-checks existence and catches
-- UniqueViolation defensively (see audio.service.ts).
--
-- IMPORTANT: This migration intentionally does NOT use
-- CREATE INDEX CONCURRENTLY. The Railway dashboard query
-- runner wraps statements in implicit transactions, and
-- PostgreSQL forbids CONCURRENTLY inside a transaction —
-- the result is a silent no-op (UI reports success, index
-- never persists). Using a plain CREATE INDEX is safe for
-- this table given:
--   1) incident_transcripts is small (single-digit rows
--      at the time of writing)
--   2) the lock from CREATE INDEX is brief (milliseconds
--      at this scale)
--   3) deploy is manual via Railway dashboard, not via
--      automated CI pipeline
-- If this project ever migrates to a CI-driven migration
-- runner that bypasses the dashboard's transaction wrapper,
-- CONCURRENTLY can be reintroduced.
--
-- Applied to production on 2026-04-29.

CREATE UNIQUE INDEX idx_transcripts_audio_unique
  ON incident_transcripts(audio_asset_id);

DROP INDEX IF EXISTS idx_transcripts_audio;
