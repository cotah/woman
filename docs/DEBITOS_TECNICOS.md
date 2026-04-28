# Débitos técnicos

Lista versionada de débitos técnicos conhecidos. Cada item registra o problema, o impacto, o caminho de fix e o esforço estimado. Atualizar ao identificar (não esperar pra "depois resolver").

Formato:
- **Título curto**
- Resumo do problema
- Impacto
- Fix proposto
- Esforço estimado
- Criado durante / referência

---

## Lint script broken (B2 follow-up)

- `npm run lint` falha porque `eslint` não está em `devDependencies` e não há config (`.eslintrc.*` ou `eslint.config.*`) no projeto.
- `npx eslint` baixa a v10.2.1, que exige flat config — falha imediata por config ausente.
- Não bloqueia `npm run build` nem `npm test`. CI atual não roda lint.
- **Fix:** adicionar `eslint`, `@typescript-eslint/parser`, `@typescript-eslint/eslint-plugin` em `devDependencies`. Criar `eslint.config.mjs` (flat config) com regras NestJS padrão. Opcional: integrar a um job do CI.
- **Esforço estimado:** 1h.
- **Criado durante:** pré-voo do B2 (commits `038340a..9805178`, 2026-04-28).

---

## `getLatestLocation` em `location.service.ts:147` — método público sem callers

- Mesmo padrão do `processTranscription`. Sem callers em `src/`. Não exposto por `location.controller.ts`.
- Marcado `@deprecated` durante o B2 e mantido **secure-by-default** (`assertOwnership` antes de operar) caso seja wired no futuro.
- **Fix:** investigar junto com `processTranscription` — provável que sejam o mesmo padrão de incompletude. Decidir entre remover ou plugar a um endpoint legítimo.
- **Esforço estimado:** investigação compartilhada com item acima.
- **Criado durante:** investigação do Passo 4 do B2 (commit `9805178`, 2026-04-28).

---

## Audio pipeline retry duplica side effects

- **Local:** `backend-api/src/modules/audio/audio.service.ts` `processTranscription`.
- **Sintoma:** se o método lançar **após** `transcriptRepo.save`, o BullMQ retenta (até 3 attempts). No retry, o método roda do início:
  - Transcript é re-criado em `incident_transcripts` (sem unique constraint em `audio_asset_id`).
  - `incident_events` `transcription_completed` e `ai_analysis_result` duplicados.
  - Risk signals (Bug 8.a: `audio_distress_detected`, `help_phrase_detected`) re-emitidos — score do incidente sobe duas vezes.
- **Probabilidade real hoje:** muito baixa. Entre o `transcriptRepo.save` e o final do método há apenas: `audioAssetRepo.update COMPLETED`, dois `createIncidentEvent` (com try/catch interno), `processRiskSignal` (com try/catch externo, não relança), e `broadcastTimelineEvent` (sync, não lança em condições normais).
- **Fix proposto:** unique constraint em `incident_transcripts.audio_asset_id` (1 transcript por chunk = invariante natural). Migration nova. Como bonus, o engine também ganharia dedup natural se aceitar dedup por `(incidentId, signal.type, payload.audioAssetId)` para signals `oncePerIncident:false` — mudança opcional.
- **Esforço estimado:** 1-2h para migration + ajuste de upsert no service. Testes precisam de cenário de retry.
- **Criado durante:** Bug 8.a fix (2026-04-28). Aceito como débito porque resolver direito exige migration de schema fora do escopo do 8.a.

---

### IncidentGateway inerte (resolvido em Fix 2 do pipeline)

- **Descoberto durante:** registro do AudioProcessor (Fix 2 do pipeline-fix).
- **Sintoma em prod até descoberta:** mobile tenta conectar `wss://.../incidents` → handshake falha ou timeout → reconnect loop perpétuo → eventos `incident:update`, `timeline:event`, `contact:response` NUNCA chegam à tela da usuária em situação de emergência.
- **Causa:** gateway declarado como classe (`src/websocket/incident.gateway.ts`), NestJS pode instanciar, mas nunca registrado como provider de módulo, então o transport WebSocket não é vinculado.
- **Origem:** mesmo initial commit `3f547a6` — padrão recorrente de "boilerplate incompleto".
- **Resolvido:** criação do `WebsocketModule` dedicado em `src/websocket/websocket.module.ts`, registrando `IncidentGateway` como provider e exportando-o. Importado pelo `AudioModule` (consumidor direto via AudioProcessor) e pelo `AppModule` (defensive wiring).

---

## Notas de processo (acumular conforme surgem)

- 2026-04-28 (durante Fix 1 do pipeline de áudio): ao consolidar entities, verificar não só imports do TYPE mas também usos como VALOR LITERAL (ex: `transcriptionStatus: 'pending'` quebra com enum strict-typed mesmo sem importar o type).

---

## Resolvidos

### processTranscription órfão (B2 follow-up)

- **Registrado em:** `7e4d54a` (durante B2, 2026-04-28).
- **Resolvido em:** `1e899bd` (Fix 4 do pipeline-fix, 2026-04-28).
- **Como:** refatoração do `AudioProcessor` para delegar ao service. `processTranscription` deixou de ser órfão e virou caller principal do pipeline (chamada pelo worker BullMQ a cada job da fila `audio-processing`). JSDoc reescrito; tag `@deprecated` removida.

### Type interface `AudioTranscriptionJobData` mente sobre runtime

- **Registrado em:** `e821ddb` (hotfix legacy-payload pós Fix 4 do pipeline-fix, 2026-04-28).
- **Resolvido em:** `1ab49e5` (cleanup batch 1, 2026-04-28).
- **Como:** `userId` marcado como opcional (`userId?: string`) na interface em `backend-api/src/queue/audio.processor.ts`, alinhando com a realidade de runtime onde payloads legacy podem chegar sem o campo. JSDoc adicionado referenciando o commit do hotfix e explicando o fallback via `getOwnerUserId`.

### CRLF nos arquivos do `backend-api`

- **Registrado em:** B2 commits (`038340a..9805178`, 2026-04-28).
- **Resolvido em:** `1ab49e5` (cleanup batch 1, 2026-04-28).
- **Como:** `.gitattributes` expandido com lista explícita de binary types (`*.png`, `*.jpg`, `*.mp3`, etc.) além da regra base `* text=auto eol=lf` que já existia desde 2026-04-13. `git add --renormalize .` confirmou que o índice já estava consistente — nenhum arquivo tracked foi tocado, o que valida que os warnings eram apenas cosméticos do working copy local.
