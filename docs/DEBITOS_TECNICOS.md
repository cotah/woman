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

## Type interface `AudioTranscriptionJobData` mente sobre runtime

- **Local:** `backend-api/src/queue/audio.processor.ts:13`.
- **Sintoma:** interface declara `userId: string` (obrigatório) mas em runtime payloads legacy (pré-Fix 4 do pipeline-fix) chegam sem o campo. TypeScript aceita silenciosamente porque `audio.service.ts` trata como `userId?: string`.
- **Risco:** nenhum funcional (fallback no service ativa e recupera userId via `getOwnerUserId`). Apenas inconsistência de tipo que pode confundir leitor futuro do código do processor.
- **Fix:** marcar `userId?: string` na interface também. 1 linha.
- **Quando:** próximo sweep de boilerplate, ou primeira vez que `audio.processor.ts` for tocado por outro motivo.
- **Criado durante:** hotfix legacy-payload pós Fix 4 do pipeline-fix (2026-04-28).

---

## CRLF nos arquivos do `backend-api`

- Git emite `warning: in the working copy of '...', CRLF will be replaced by LF the next time Git touches it` em alguns arquivos editados durante o B2.
- Indica inconsistência de line endings entre Windows (CRLF) e a normalização do repo (LF).
- Não causa erro, mas suja diffs e pode confundir blame em futuras edições.
- **Fix:** adicionar `.gitattributes` com `* text=auto eol=lf` (ou normalizar manualmente com `git add --renormalize .`).
- **Esforço estimado:** 15min.
- **Criado durante:** commits do B2 (2026-04-28).

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
