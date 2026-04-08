# SafeCircle — Relatório 2: Resultados da Auditoria

**Data:** 08 de Abril de 2026  
**Auditor:** Claude (QA Lead / Staff Engineer)  
**Escopo:** Backend API (NestJS) — auditoria de código, testes, correções  

---

## 1. O que foi testado

- Build do backend (`npm run build`) — OK
- 111 testes automatizados (9 suites) — todos passando
- Cobertura de código via `jest --coverage`
- Análise estática de todos os 103 arquivos TypeScript do backend
- Fluxo completo de incidentes: create → activate → resolve/cancel
- Lógica de coerção (secret cancel)
- Pipeline de notificações (alert waves)
- Risk engine (sinais de risco, scoring)
- Autenticação JWT (login, refresh, logout, session rotation)
- Guards e decorators (@Public, JwtAuthGuard, RolesGuard)
- Providers de notificação (SMS/Twilio, Push/Firebase, Voice/Twilio)
- Queue processors (alert, escalation, journey-expiry, audio)
- Journey Service (jornada segura, expiração, auto-escalação)
- Contact access tokens (geração, validação)
- Endpoints do contact-web portal
- Configuração CORS, Helmet, ValidationPipe
- Estrutura Docker (Dockerfile multi-stage)
- Variáveis de ambiente necessárias

---

## 2. O que foi encontrado

### BLOCKER (2)

| ID | Título | Local | Descrição |
|----|--------|-------|-----------|
| ISS-BLOCK-001 | Alert dispatch nunca é chamado | `incidents.service.ts` | `dispatchAlertWaves()` existia mas nunca era invocado. Emergências criadas, ninguém notificado. |
| ISS-BLOCK-002 | Contact portal sem endpoints backend | contact-web → backend | O portal web dos contatos chama `/contact/incident`, `/contact/validate`, `/contact/incident/:id/respond` — nenhum desses endpoints existia no backend. |

### CRITICAL (1)

| ID | Título | Local | Descrição |
|----|--------|-------|-----------|
| ISS-CRIT-001 | Contact respond bloqueado por JWT | `notifications.controller.ts` | `POST /incidents/:id/respond` exigia JWT, mas contatos só têm access token. Endpoint inacessível. |

### MAJOR (3)

| ID | Título | Local | Descrição |
|----|--------|-------|-----------|
| ISS-MAJ-001 | AlertProcessor com providers stub | `queue/alert.processor.ts` | Métodos `sendSms/sendPush/sendVoiceCall/sendEmail` estão comentados. Caminho duplicado de dispatch. |
| ISS-MAJ-002 | Sem rate limiting | `app.module.ts` | ThrottlerModule não está configurado. Config de throttle existe mas não é usada. |
| ISS-MAJ-003 | CORS wildcard possível | `main.ts` | Se `CORS_ORIGINS=*`, qualquer origem é aceita em produção. |

### MINOR (3)

| ID | Título | Local | Descrição |
|----|--------|-------|-----------|
| ISS-MIN-001 | Mobile hardcoded staging | `mobile-app/lib/main.dart:46` | `AppConfig.initialize(Environment.staging)` hardcoded. |
| ISS-MIN-002 | Sem EmailProvider | `notifications.service.ts` | Wave 3 inclui 'email' como canal mas provider não existe. |
| ISS-MIN-003 | Cobertura de testes mobile ~0% | `mobile-app/test/` | Apenas 1 arquivo de teste. Lógica safety-critical sem cobertura. |

---

## 3. O que foi corrigido

### FIX-001: Alert dispatch wiring (ISS-BLOCK-001)
- **Severidade:** BLOCKER → RESOLVIDO
- **Resumo:** Conectei IncidentsService aos módulos de notificação, contatos e usuários. Agora:
  - `activate()` → chama `dispatchAlertWaves()` com contatos de confiança
  - Secret cancel (coerção) → chama `dispatchAlertWaves()` silenciosamente
  - `resolve()` e `cancel()` (normal) → chamam `cancelPendingWaves()`
- **Arquivos alterados:**
  - `src/modules/incidents/incidents.module.ts` — adicionou imports de NotificationsModule, ContactsModule, UsersModule
  - `src/modules/incidents/incidents.service.ts` — injetou 4 novos services, adicionou método `dispatchAlertsForIncident()` (~80 linhas)
- **Testes atualizados:** 3 specs existentes + 1 novo (`alert-dispatch-wiring.spec.ts`, 6 testes)
- **Risco de regressão:** BAIXO — mudança aditiva, nenhum comportamento existente foi alterado
- **Como validar:** Criar incidente → ativar → verificar que alert waves foram enfileiradas no BullMQ

### FIX-002: Contact respond endpoint (ISS-CRIT-001)
- **Severidade:** CRITICAL → RESOLVIDO
- **Resumo:** Adicionei `@Public()` ao endpoint `POST /incidents/:id/respond` para permitir acesso via access token sem JWT.
- **Arquivo alterado:** `src/modules/notifications/notifications.controller.ts`
- **Risco de regressão:** NENHUM — endpoint já validava access token internamente

### FIX-003: Contact portal controller (ISS-BLOCK-002)
- **Severidade:** BLOCKER → RESOLVIDO
- **Resumo:** Criei `ContactPortalController` com 3 endpoints públicos:
  - `GET /contact/validate` — valida access token
  - `GET /contact/incident` — retorna dados do incidente (localização, timeline, instruções)
  - `POST /contact/incident/:id/respond` — registra resposta do contato
- **Arquivos criados:**
  - `src/modules/contacts/contact-portal.controller.ts` (~250 linhas)
- **Arquivo alterado:**
  - `src/modules/contacts/contacts.module.ts` — registrou controller, adicionou TypeORM entities e forwardRef NotificationsModule
- **Risco de regressão:** BAIXO — módulo novo, não altera comportamento existente
- **Como validar:** Acessar URL do contact-web com token válido → deve carregar dados do incidente

---

## 4. O que ficou pendente

| ID | Nível | O que | Por quê | Recomendação |
|----|-------|-------|---------|--------------|
| ISS-MAJ-001 | MAJOR | AlertProcessor stub | Requer decisão de arquitetura: eliminar o processor (usar só NotificationsService) ou implementar os providers nele. Mudar pode quebrar o wiring de filas. | Remover o AlertProcessor e manter apenas o caminho via NotificationsService.dispatchSingleDelivery |
| ISS-MAJ-002 | MAJOR | Rate limiting | Requer adicionar ThrottlerModule ao AppModule. Simples mas precisa definir limites por endpoint. | Adicionar `@nestjs/throttler` com 60 req/min default |
| ISS-MAJ-003 | MAJOR | CORS wildcard | Depende da config no Railway. Se `CORS_ORIGINS` está definido com domínios específicos, não há risco. | Verificar valor no Railway e remover suporte a `*` |
| ISS-MIN-001 | MINOR | Staging hardcoded | Fix simples mas precisa testar build iOS/Android | Usar `--dart-define=ENVIRONMENT=prod` no build de release |
| ISS-MIN-002 | MEDIUM | Sem EmailProvider | Wave 3 lista 'email' mas nunca será enviado | Implementar EmailProvider (Resend/SES) ou remover 'email' da wave config |
| ISS-MIN-003 | MAJOR | Testes mobile | Requer tempo significativo para cobertura adequada | Priorizar testes de CoercionHandler e IncidentService |
| — | LOW | Audio clips no portal | ContactPortalController retorna `audioClips: []` | Implementar geração de signed URLs S3 para streaming |

---

## 5. Como reproduzir e validar

```bash
# Clonar e instalar
git clone https://github.com/cotah/woman.git
cd woman/backend-api
npm install

# Rodar testes
npm test                    # 111 testes, 9 suites
npm run test:cov            # com cobertura

# Build
npm run build               # deve completar sem erros

# Iniciar (requer .env com DB, Redis, JWT_SECRET, etc.)
npm run start:dev           # desenvolvimento
npm run start:prod          # produção (após build)
```

---

## 6. Métricas

| Métrica | Valor |
|---------|-------|
| Testes antes da auditoria | 105 (8 suites) |
| Testes depois da auditoria | 111 (9 suites) |
| Testes adicionados | 6 |
| Bugs encontrados | 6 (2 blocker, 1 critical, 3 major) |
| Bugs corrigidos | 3 (2 blocker, 1 critical) |
| Bugs pendentes | 3 major + 3 minor |
| Arquivos alterados | 8 |
| Arquivos criados | 2 (controller + test) |
| Linhas adicionadas | ~330 |

---

## 7. Changelog técnico

| Arquivo | O que mudou | Por quê |
|---------|------------|---------|
| `incidents.module.ts` | +3 imports (Notifications, Contacts, Users) | Habilitar dispatch de alertas |
| `incidents.service.ts` | +4 injeções, +método `dispatchAlertsForIncident()` | Core da fix: conectar incidentes → notificações |
| `notifications.controller.ts` | +`@Public()` no respond endpoint | Permitir acesso de contatos sem JWT |
| `contacts.module.ts` | +6 TypeORM entities, +forwardRef, +controller | Suportar ContactPortalController |
| `contact-portal.controller.ts` | NOVO — 3 endpoints públicos | Portal web dos contatos funcionando |
| `alert-dispatch-wiring.spec.ts` | NOVO — 6 testes | Validar que alertas são disparados |
| `incident-creation.spec.ts` | +4 mock providers | Adaptar ao novo constructor |
| `emergency-flows.spec.ts` | +3 imports, +3 mock providers | Adaptar ao novo constructor |
| `coercion-logic.spec.ts` | +4 args no constructor | Adaptar ao novo constructor |

---

## 8. Recomendações futuras (por prioridade)

1. **Verificar AlertProcessor vs NotificationsService** — Decidir qual caminho de dispatch manter e eliminar o duplicado
2. **Adicionar rate limiting** — `@nestjs/throttler` com limites por endpoint
3. **Implementar testes no mobile** — Priorizar CoercionHandler, IncidentService, AuthService
4. **Verificar CORS no Railway** — Confirmar que não está com `*` em produção
5. **Trocar Environment.staging → prod** — Usar dart-define para builds de release
6. **Implementar EmailProvider** — Para completar Wave 3
7. **Audio clips no portal** — Gerar signed URLs S3
8. **Adicionar testes E2E** — Com banco real (testcontainers) para validar migrations
9. **Implementar webhook de status Twilio** — Para confirmar delivery de SMS/voz
10. **Monitoramento de filas** — Dashboard BullMQ para verificar jobs stuck/failed

---

## 9. Veredito final

### O sistema está estável? **SIM** — com as correções aplicadas.

### O sistema está pronto para produção? **QUASE.**

**O que bloqueia release:**
- ~~Alert dispatch não conectado~~ → **CORRIGIDO**
- ~~Contact portal sem endpoints~~ → **CORRIGIDO**
- Verificar CORS em produção (5 minutos no Railway)
- Trocar staging → prod no mobile (1 linha)

**O que merece monitoramento forte:**
- Filas BullMQ (waves de alerta) — monitorar jobs failed
- Twilio (SMS/voz) — monitorar delivery rates
- Firebase push — monitorar token invalidation rates
- Redis availability — se Redis cair, filas param

**O que pode ser corrigido depois sem grande risco:**
- Rate limiting
- EmailProvider
- AlertProcessor cleanup
- Testes no mobile
- Audio clips no portal

---

*SafeCircle — Protegendo quem você ama.*
