# ADR-001: NestJS as Backend Framework

## Status: Accepted

## Context
We need a production-grade Node.js backend framework that supports:
- Modular architecture
- Strong typing (TypeScript)
- Built-in dependency injection
- WebSocket support
- Queue integration
- Testing infrastructure

## Decision
Use NestJS with TypeORM for the backend API.

## Consequences
- Strong module boundaries enforce clean architecture
- Built-in guards/interceptors for auth and audit
- Native WebSocket gateway support for live updates
- BullMQ integration via @nestjs/bullmq
- Mature ecosystem with production track record
