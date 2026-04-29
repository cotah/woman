-- Migration: Prevent duplicate transcripts on BullMQ retry
--
-- After Fix 4 of the audio pipeline (commit 1e899bd, 2026-04-28),
-- processTranscription persists a transcript and then runs a chain
-- of side effects (incident_events, risk signals, real-time
-- broadcast). If the method throws AFTER transcriptRepo.save,
-- BullMQ retries the same job and re-creates everything, including
-- a duplicate row in incident_transcripts.
--
-- Each audio chunk = exactly 1 transcript = natural invariant.
-- This UNIQUE constraint enforces it at the DB level. The service
-- layer also pre-checks existence (skip retry early) and catches
-- UniqueViolation as defense in depth (see audio.service.ts).
--
-- CONCURRENTLY: avoids the ACCESS EXCLUSIVE lock that a regular
-- CREATE/DROP INDEX would acquire. Both statements MUST run
-- outside of a transaction (PostgreSQL rule). Run them as two
-- separate statements in Railway's SQL console.

CREATE UNIQUE INDEX CONCURRENTLY idx_transcripts_audio_unique
  ON incident_transcripts(audio_asset_id);

DROP INDEX CONCURRENTLY IF EXISTS idx_transcripts_audio;
