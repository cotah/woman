# ADR-002: Event-Sourced Incident Timeline

## Status: Accepted

## Context
Incidents require a complete, tamper-resistant record of all events for safety and potential evidentiary purposes.

## Decision
Use an append-only event model for incident timelines. Each event is an immutable record with type, timestamp, payload, and source.

## Consequences
- Timeline is reconstructable from events
- No data loss from overwrites
- Audit-grade record keeping
- Slightly more storage, but acceptable for safety-critical data
- Phase 2 can replay events for analysis
