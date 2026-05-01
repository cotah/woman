-- Migration: Enforce one row per (user, push_token) on user_devices
--
-- The user_devices table was created in migration 001 but has no UNIQUE
-- constraint protecting against duplicate (user_id, push_token) pairs.
-- The mobile app may call POST /users/me/devices on every login or token
-- refresh — we want UPSERT semantics rather than ever-growing duplicate
-- rows for the same physical device.
--
-- A composite UNIQUE index lets the service layer use:
--
--   INSERT ... ON CONFLICT (user_id, push_token) DO UPDATE
--     SET is_active = true, last_seen_at = NOW(), ...
--
-- Postgres allows multiple NULLs in a composite UNIQUE index by default,
-- so legacy or pre-token rows with NULL push_token are not blocked.
--
-- IMPORTANT: This migration intentionally does NOT use CREATE INDEX
-- CONCURRENTLY. The Railway dashboard query runner wraps statements in
-- implicit transactions, and PostgreSQL forbids CONCURRENTLY inside a
-- transaction — the result is a silent no-op. Using a plain CREATE
-- UNIQUE INDEX is safe for this table given:
--   1) user_devices is currently empty (no endpoint registered devices
--      until this push patch ships)
--   2) the lock is brief (milliseconds at this scale)
--   3) deploy is manual via Railway dashboard
--
-- Apply manually via Railway dashboard after backend deploy.

CREATE UNIQUE INDEX idx_user_devices_user_pushtoken_unique
  ON user_devices(user_id, push_token);
