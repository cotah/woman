# SafeCircle — Relatório 1: Plano de Teste

**Data:** 08 de Abril de 2026  
**Auditor:** Claude (QA Lead / Staff Engineer)  
**Versão do Repo:** branch `main`, commit mais recente  

---

## 1. Resumo do Projeto

O SafeCircle é uma plataforma de segurança pessoal composta por:

- **Mobile App** (Flutter/Dart) — app principal para iOS, Android e Web
- **Backend API** (NestJS/TypeScript) — servidor REST + WebSocket
- **Admin Web** (React/Vite) — dashboard administrativo
- **Contact Web** (React/Vite) — portal para contatos de confiança verem emergências
- **Shared Types** — tipos compartilhados entre os projetos web

**Objetivo funcional:** Permitir que o usuário dispare alertas de emergência que notificam contatos de confiança com localização em tempo real, gravação de áudio, avaliação de risco por IA, e escalação progressiva em ondas.

**Stack identificada:**
- Backend: NestJS 10 + TypeORM + PostgreSQL + Redis (BullMQ) + Sentry
- Mobile: Flutter 3.19+ / Dart 3.3+ com Provider, GoRouter, flutter_map
- Web: React + Vite + TypeScript
- Infra: Railway (Docker), deploy automático via GitHub
- Serviços externos: Twilio (SMS/voz), Firebase (push), Mapbox (mapas), Deepgram (transcrição), OpenAI (classificação de áudio), AWS S3 (armazenamento de áudio)

**Dimensão do código:**
- ~29.400 linhas de código
- 103 arquivos TypeScript no backend
- 59 arquivos Dart no mobile
- 25 arquivos no admin-web
- 13 arquivos no contact-web
- 8 suites de teste / 105 testes unitários (todos passando)

---

## 2. Mapa Técnico do Sistema

### Backend — 14 Módulos

| Módulo | Arquivos principais | Responsabilidade |
|--------|-------------------|------------------|
| Auth | auth.service, auth.controller, jwt.strategy | Login, registro, JWT + refresh token rotation |
| Users | users.service, users.controller | Perfil, dispositivos, sessões |
| Incidents | incidents.service, incidents.controller | Ciclo completo de emergência (criar → ativar → cancelar/resolver) |
| Contacts | contacts.service, contacts.controller, contact-access.service | Contatos de confiança, verificação, tokens de acesso |
| Settings | settings.service, settings.controller | Config de emergência, PIN de coerção |
| Location | location.service, location.controller | GPS em tempo real |
| Audio | audio.service, audio.controller, deepgram.provider, ai-classifier.provider | Upload S3, transcrição, classificação IA |
| Notifications | notifications.service, notifications.controller, sms/push/voice providers | Alertas em ondas (SMS, push, voz) |
| Risk Engine | risk-engine.service, risk-rules.config | Pontuação de risco 0-100 |
| Timeline | timeline.service, timeline.controller | Linha do tempo unificada |
| Journey | journey.service, journey.controller | Jornada Segura + auto-escalação |
| Audit | audit.service | Logs imutáveis |
| Admin | admin.service, admin.controller, admin.guard | Dashboard admin |
| Health | health.service, health.controller | Health checks |
| Feature Flags | feature-flags.service | Feature toggles por fase |

### Queue Processors (BullMQ)
- `alert.processor.ts` — Dispatch de alertas individuais (SMS, push, voz, email)
- `escalation.processor.ts` — Orquestração de ondas de escalação
- `journey-expiry.processor.ts` — Expiração de jornadas seguras
- `audio.processor.ts` — Processamento assíncrono de áudio

### WebSocket
- `incident.gateway.ts` — Gateway Socket.IO para updates em tempo real

### Mobile App — Estrutura

| Camada | Componentes |
|--------|------------|
| Core/API | api_client, api_endpoints |
| Core/Auth | auth_service, auth_state |
| Core/Services | incident, location, audio, websocket, notification, contacts, settings, journey, offline_queue, sms_fallback, background, alarm, discretion |
| Core/Utils | coercion_handler |
| Core/Config | env, app_config, router |
| Core/Theme | app_theme, theme_notifier |
| Features | emergency (countdown, active, screen), journey (screen, active), contacts (add, list), settings (emergency, coercion PIN, audio, privacy), dashboard, auth (login, register), diagnostics, incidents (history, detail), test_mode, disguise (calculator), onboarding, help |

---

## 3. Detecção de Ambiente

| Item | Detectado |
|------|-----------|
| Backend package manager | npm (package-lock.json presente) |
| Frontend mobile | Flutter/Dart (pubspec.yaml) |
| Frontend web | npm + Vite |
| Framework backend | NestJS 10 |
| Framework mobile | Flutter 3.19+ |
| DB | PostgreSQL (via TypeORM) |
| Cache/Filas | Redis + BullMQ |
| Docker | Dockerfile multi-stage (node:20-alpine) |
| docker-compose | Sim (infrastructure/docker/) |
| Makefile | Não |
| Scripts | scripts/setup-local.sh |
| Testes | Jest (backend), flutter_test (mobile — 1 arquivo) |
| CI/CD | GitHub → Railway (deploy automático) |
| Monitoramento | Sentry (@sentry/nestjs) |

---

## 4. Matriz de Componentes e Estratégia de Teste

### PRIORIDADE CRÍTICA (safety-critical)

| Componente | O que testar | Risco | Prioridade |
|-----------|-------------|-------|------------|
| **Incidents Service** (create/activate/cancel/resolve) | Todos os estados, transições, validações, idempotência | CRÍTICO — é o core do app | P0 |
| **Secret Cancel (coerção)** | PIN de coerção → backend escalona silenciosamente enquanto UI mostra cancelado | CRÍTICO — funcionalidade de segurança de vida | P0 |
| **Notification Waves** | 3 ondas disparam na sequência correta, com delay, nos canais certos | CRÍTICO — se não alertar, app falha no propósito | P0 |
| **Journey Expiry → Incident Escalation** | Jornada expira → cria incidente automaticamente | ALTO | P0 |
| **Auth (JWT + Refresh)** | Login, refresh token rotation, logout, sessões revogadas | ALTO | P0 |

### PRIORIDADE ALTA

| Componente | O que testar | Risco | Prioridade |
|-----------|-------------|-------|------------|
| Risk Engine | Sinais de risco calculam score correto, coerção = critical | ALTO | P1 |
| Audio Upload + Transcription | Upload S3, Deepgram transcreve, IA classifica | MÉDIO | P1 |
| Location tracking | GPS chega ao backend, persiste, WebSocket broadcast | ALTO | P1 |
| Contact Access | Token de acesso do contato, portal web funciona | ALTO | P1 |
| SMS/Voice/Push Providers | Twilio envia SMS/voz, Firebase envia push, dry-run mode | ALTO | P1 |

### PRIORIDADE MÉDIA

| Componente | O que testar | Risco | Prioridade |
|-----------|-------------|-------|------------|
| Admin Dashboard | Login admin, listagem de incidentes, audit logs, feature flags | MÉDIO | P2 |
| Timeline | Eventos na ordem certa, sem internals vazando | MÉDIO | P2 |
| Settings | Salvar/carregar config de emergência, PIN de coerção | MÉDIO | P2 |
| Health Check | Endpoint /health retorna status de DB, Redis | BAIXO | P2 |

---

## 5. Issues Já Identificadas na Varredura Estática

### ISS-001: AlertProcessor com providers stub (MAJOR)
**Local:** `queue/alert.processor.ts`  
**Descrição:** Os métodos `sendSms()`, `sendPush()`, `sendVoiceCall()`, `sendEmail()` estão com implementação comentada ("In production, inject and call..."). O processor apenas loga mas não envia nada de verdade.  
**Impacto:** Existe uma duplicidade de caminhos de dispatch — o `NotificationsService.dispatchSingleDelivery()` usa os providers corretamente, mas o `AlertProcessor` não. Se o sistema usar o queue path via `AlertProcessor`, alertas não seriam enviados.  
**Risco:** ALTO — precisa verificar qual path é realmente usado em produção.

### ISS-002: Mobile hardcoded em Environment.staging (MINOR)
**Local:** `mobile-app/lib/main.dart:46`  
**Descrição:** `AppConfig.initialize(Environment.staging)` está hardcoded. Há um FIXME comentário mas não há lógica de --dart-define.  
**Impacto:** Builds de produção apontam para staging.

### ISS-003: CORS com wildcard em produção (MAJOR)
**Local:** `backend-api/src/main.ts:56-66`  
**Descrição:** Se `CORS_ORIGINS` for `'*'`, permite qualquer origem. Em produção isso é um risco de segurança.  
**Risco:** Depende do valor configurado no Railway.

### ISS-004: Swagger exposto (verificar)
**Local:** `backend-api/src/main.ts:83`  
**Descrição:** Swagger está desabilitado em produção (`nodeEnv !== 'production'`). Precisa confirmar que `NODE_ENV=production` está setado no Railway.

### ISS-005: Cobertura de testes no mobile quase zero
**Local:** `mobile-app/test/`  
**Descrição:** Apenas 1 arquivo de teste no mobile. Toda a lógica de CoercionHandler, services e fluxos está sem testes automatizados.

---

## 6. Critérios de Pass/Fail

| Critério | Aprovado | Reprovado |
|----------|----------|-----------|
| Testes existentes | 105/105 passando | Qualquer falha |
| Fluxo de emergência | Create → Activate → Resolve funciona end-to-end | Qualquer quebra no fluxo |
| PIN de coerção | Secret cancel retorna "cancelled" ao client mas mantém incident ativo no backend | Se vazar status real pro client |
| Alertas em ondas | Wave 1, 2, 3 disparadas com delays corretos | Se waves não forem enfileiradas |
| Jornada Segura | Expiry → cria incidente automático | Se expiry silenciar |
| Auth | Login, refresh, logout consistentes | Token expirado aceito, refresh sem rotation |
| Providers | SMS/Push/Voice enviam ou operam em dry-run sem crash | Crash em provider não tratado |
| Build backend | `npm run build` sem erros | Erro de compilação |
| Build mobile | `flutter build web` sem erros | Erro de compilação |

---

## 7. Checklist de Qualidade

- [ ] `npm run build` (backend) — sem erros
- [ ] `npx jest` — 105/105 passando
- [ ] Verificar TypeScript strict mode
- [ ] Verificar imports quebrados
- [ ] Verificar variáveis de ambiente necessárias documentadas
- [ ] Verificar Dockerfile build funciona
- [ ] Verificar consistência de tipos entre shared-types e backend
- [ ] Verificar que eventos internos (isInternal=true) não vazam para o client

---

## 8. Áreas Críticas e Riscos

### Riscos CRÍTICOS
1. **PIN de coerção** — Se o frontend vazar o status real do incidente (escalated em vez de cancelled), a segurança do usuário é comprometida
2. **Dual dispatch path** — AlertProcessor (stub) vs NotificationsService (real). Precisa confirmar qual é usado
3. **Journey expiry em produção** — Se o Redis perder o job de expiry, a jornada nunca escala para incidente

### Riscos ALTOS
4. **Twilio credentials em produção** — Se inválidas, alertas SMS/voz falham silenciosamente (dry-run mode)
5. **Firebase push** — Se credentials inválidas, push falha silenciosamente
6. **Audio upload sem validação de tipo/tamanho** — Potencial para uploads maliciosos

### Riscos MÉDIOS
7. **Sem rate limiting configurado no NestJS** — Throttle está no config mas não vi ThrottlerModule no app.module
8. **Sem email provider implementado** — Wave 3 inclui 'email' como canal mas não há EmailProvider
9. **Environment hardcoded como staging no mobile** — Builds de release apontam para staging

---

## 9. Próximos Passos

Vou agora executar a auditoria na seguinte ordem:

1. Build do backend (`npm run build`)
2. Rodar todos os testes existentes com cobertura
3. Análise estática dos módulos críticos
4. Verificar consistência do dual dispatch path
5. Verificar que secret cancel não vaza dados reais
6. Verificar entities e migrations
7. Verificar segurança (auth guards, validation pipes, CORS real)
8. Corrigir issues encontradas (uma por vez, com teste)
9. Gerar Relatório 2 com resultados

---

*Relatório gerado automaticamente durante auditoria do SafeCircle.*
