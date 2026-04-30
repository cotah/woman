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

## Lint baseline com 149 warnings legacy

- ESLint funcional desde `290e62a` (2026-04-29). `npm run lint` retorna exit 0 com 149 warnings em código pré-existente.
- **Sintoma:** warnings em código legacy. Não são errors — pipeline passa — mas indicam código que poderia ser tipado mais estritamente.
- **Distribuição:**
  - `@typescript-eslint/no-explicit-any`: **149 ocorrências** (~119 em test files com mocks `: any`, ~30 em src/ — payloads JSON em entities, response handlers de SDKs externos como Twilio e Deepgram).
- **Decisão:** baseline aceito. Novos códigos devem respeitar todas as regras (warnings também). Limpeza legacy fica como sweep futuro, sem urgência. Pipeline não trava.
- **Esforço estimado pra limpar:**
  - Test files (~119 warnings): 4-6h substituindo `: any` por tipos de mock (`jest.Mocked<T>`, `Partial<T>`, `DeepPartial`).
  - Src files (~30 warnings): 1-2h tipando payloads JSON e responses de SDKs.
  - **Total: ~6-8h** num sweep dedicado.
- **Criado durante:** fix de "Lint script broken" (`290e62a`, 2026-04-29).

---

### Convenção `@Req` vs `@CurrentUser` inconsistente

- **Local:** `tracking.controller.ts` usa `@Req() req: RequestWithUser`; resto do projeto usa `@CurrentUser() user: AuthenticatedUser`.
- **Sintoma:** outlier de convenção. Não bloqueia funcionalidade, mas confunde leitor que esperaria padrão único.
- **Fix proposto:** refator de `tracking.controller.ts` pros 9 endpoints usarem `@CurrentUser()`. ~30 min.
- **Quando:** quando alguém estiver mexendo em `tracking.controller.ts` por outro motivo.
- **Descoberto durante:** PR 1B do lint sweep (`e149010`, 2026-04-30).

---

### `JwtAuthGuard` com nomes idênticos em paths diferentes

- **Sintoma:** 2 classes `JwtAuthGuard` no projeto: `src/common/guards/jwt-auth.guard.ts` (versão completa com `IS_PUBLIC_KEY`/Reflector) e `src/modules/auth/guards/jwt-auth.guard.ts` (apenas `extends AuthGuard('jwt')`). Pode ser dead code (uma não usada) ou duplicação intencional.
- **Risco:** confusão de import em refactor futuro; possível dead code não detectado.
- **Fix proposto:** investigar callers de cada uma. Se uma não tem callers, remover. Se ambas em uso, renomear pra distinguir propósito.
- **Esforço estimado:** 30-60 min.
- **Descoberto durante:** PR 1B do lint sweep (`e149010`, 2026-04-30).

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

### `getLatestLocation` órfão (B2 follow-up)

- **Registrado em:** `9805178` (durante B2, 2026-04-28).
- **Resolvido em:** `4307719` (remoção isolada, 2026-04-28).
- **Como:** método removido. A funcionalidade que ele proveria ("última localização do incident") já está coberta pelos campos `lastLatitude` / `lastLongitude` / `lastLocationAt` da `Incident` entity (snapshot O(1) atualizado a cada upload de location). Mobile e admin já consomem esses campos. Adicionar `getLatestLocation` como segunda fonte de verdade criaria risco de drift sem benefício funcional.

### Lint script broken (B2 follow-up)

- **Registrado em:** B2 commits (`038340a..9805178`, 2026-04-28).
- **Resolvido em:** `290e62a` (lint fix, 2026-04-29).
- **Como:** `eslint`, `@typescript-eslint/parser` e `@typescript-eslint/eslint-plugin` instalados em devDependencies. Criada `backend-api/eslint.config.mjs` (flat config) com regras conservadoras (`no-unused-vars` error com ignore patterns `^_`; `no-explicit-any` e `no-console` warn, com override desabilitando `no-console` em `**/database/seeds/**`). Script `lint` separado em `lint` (check-only) e `lint:fix` (opt-in explícito). Os 24 errors flagged na primeira execução foram corrigidos no mesmo commit (20 imports órfãos + 4 vars de teste + 1 arg + 1 var local com retorno descartado). 4 directives `eslint-disable-next-line @typescript-eslint/no-var-requires` órfãs nos providers de notification (push/sms/voice) também removidas. Permanecem 149 warnings (todas `no-explicit-any`) registradas como débito separado.

### Audio pipeline retry duplica side effects

- **Registrado em:** `cac6a15` (Bug 8.a fix, 2026-04-28).
- **Resolvido em:** `fe53fce` (last Major debt, 2026-04-29).
- **Como:** três camadas de defesa adicionadas: (1) UNIQUE constraint em `incident_transcripts.audio_asset_id` via migration `004_unique_transcript_per_audio_asset.sql` (executada manualmente em prod via Railway dashboard, padrão do projeto com `synchronize:false`); (2) pre-check em `transcriptRepo.exists()` imediatamente após `assertOwnership`, antes de chamadas pagas (Deepgram/OpenAI) e mutação de status — preserva status terminal da run anterior em retry (FAILED ou COMPLETED); (3) try/catch defensivo ao redor de `transcriptRepo.save` com check de `error.code === '23505'` (UniqueViolation) para casos de pre-check perder (theoretical only — same job, single worker). 2 specs novos em `audio-pipeline.spec.ts` validam ambas as camadas. Test count 129 → 131. Zero duplicatas em prod confirmadas via SELECT antes do fix (pipeline só rodou end-to-end a partir de Fix 4 / `1e899bd`).
