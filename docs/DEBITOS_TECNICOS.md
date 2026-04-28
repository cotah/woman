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

## `processTranscription` em `audio.service.ts:171` — método público sem callers

- Definido em `src/modules/audio/audio.service.ts:171`. Grep em `src/`: zero callers.
- O worker de fila (`src/queue/audio.processor.ts`) faz transcrição em paralelo, contra entidade diferente (`IncidentAudioAsset`, não `AudioAsset`). Pode ser dead code ou wire faltando.
- **Não está exposto por endpoint** — fora do raio de IDOR. Marcado `@deprecated` durante o B2.
- **Fix:**
  - (a) Se for dead code: remover. Atenção a entidades/tabelas que só esse caminho usaria.
  - (b) Se for wire faltando: rotear `audio.processor.ts` para chamar este service em vez de duplicar lógica.
- **Esforço estimado:** 30min investigação + 1–4h dependendo do caminho.
- **Criado durante:** investigação do Passo 3 do B2 (commit `02fd788`, 2026-04-28).

---

## `getLatestLocation` em `location.service.ts:147` — método público sem callers

- Mesmo padrão do `processTranscription`. Sem callers em `src/`. Não exposto por `location.controller.ts`.
- Marcado `@deprecated` durante o B2 e mantido **secure-by-default** (`assertOwnership` antes de operar) caso seja wired no futuro.
- **Fix:** investigar junto com `processTranscription` — provável que sejam o mesmo padrão de incompletude. Decidir entre remover ou plugar a um endpoint legítimo.
- **Esforço estimado:** investigação compartilhada com item acima.
- **Criado durante:** investigação do Passo 4 do B2 (commit `9805178`, 2026-04-28).

---

## CRLF nos arquivos do `backend-api`

- Git emite `warning: in the working copy of '...', CRLF will be replaced by LF the next time Git touches it` em alguns arquivos editados durante o B2.
- Indica inconsistência de line endings entre Windows (CRLF) e a normalização do repo (LF).
- Não causa erro, mas suja diffs e pode confundir blame em futuras edições.
- **Fix:** adicionar `.gitattributes` com `* text=auto eol=lf` (ou normalizar manualmente com `git add --renormalize .`).
- **Esforço estimado:** 15min.
- **Criado durante:** commits do B2 (2026-04-28).

---

## Notas de processo (acumular conforme surgem)

- 2026-04-28 (durante Fix 1 do pipeline de áudio): ao consolidar entities, verificar não só imports do TYPE mas também usos como VALOR LITERAL (ex: `transcriptionStatus: 'pending'` quebra com enum strict-typed mesmo sem importar o type).
