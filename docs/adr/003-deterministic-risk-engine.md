# ADR-003: Deterministic Risk Engine for Phase 1

## Status: Accepted

## Context
Risk scoring must be explainable, auditable, and reliable. ML-based scoring is planned for Phase 2 but Phase 1 must not depend on probabilistic models for emergency activation.

## Decision
Implement a rule-based, configuration-driven risk scoring engine. Each rule has a signal type, score delta, and human-readable reason. The engine exposes a strategy interface for Phase 2 replacement.

## Consequences
- Every score change is traceable to a specific rule
- No black-box emergency decisions
- Easy to tune thresholds via configuration
- Phase 2 can add ML scoring alongside or as replacement via strategy pattern
