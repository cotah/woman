# Investigação — Pipeline de Áudio Quebrado

**Data:** 2026-04-28
**Escopo:** Auditoria do pipeline de transcrição/análise de áudio do backend SafeCircle. Sem alteração de código.
**Status do pipeline em produção:** **0% funcional desde o initial commit (3f547a6, 2026-04-07).**

---

## Sumário executivo

O briefing original presumia que o pipeline rodava com transcrição placeholder. **A realidade é mais grave:** o pipeline nunca rodou em produção porque **três bugs estruturais sobrepostos no initial commit** impedem o worker de existir em runtime.

| # | Bug | Impacto |
|---|-----|---------|
| 1 | `AudioProcessor` definido em `src/queue/audio.processor.ts` mas **não registrado em nenhum módulo** | NestJS nunca instancia o worker. Classe é inerte. |
| 2 | Producer enfileira em `'audio-processing'`, consumer escutaria `'audio'` (mas Bug #1 já mata o worker antes) | Mesmo se o worker existisse, escutaria a fila errada. |
| 3 | `AudioAsset` e `IncidentAudioAsset` mapeiam a **mesma tabela** `incident_audio_assets`. Idem `Transcript` vs `IncidentTranscript` em `incident_transcripts`. | Padrão idêntico ao `IncidentLocation` do B2. Hoje é dead code (worker não roda). Vira hard blocker assim que o Bug #1 for corrigido. |

**Confirmação empírica obtida pelo Henrique** (28/04/2026, ~03:50):
- Postgres prod: `incident_audio_assets` tem 1 row, `transcription_status='pending'` desde 02:13:25 (~1h40min sem mover).
- Postgres prod: `incident_transcripts` tem **0 rows** (zero desde o início do projeto).
- Redis prod: `bull:audio-processing:wait` tem 1 job aguardando indefinidamente. Nenhum worker registrado para a queue.
- Redis prod: `bull:alert-dispatch` e `bull:journey-expiry` têm `:stalled-check` ativo (workers rodando), confirmando que a infraestrutura BullMQ funciona — só `audio-processing` está abandonada.

**Custo financeiro:** $0/mês. `DeepgramProvider` e `AiClassifierProvider` estão instanciados mas zero requests.

**Hipótese da origem:** refactor incompleto / boilerplate copiado e não terminado de wirar. Os 3 bugs nasceram juntos no commit `3f547a6 "Initial commit - SafeCircle pilot ready"` (Henrique, 2026-04-07).

**Recomendação:** **Abordagem A** — worker chama o service. Lógica de domínio (Deepgram + AiClassifier) já está em `audio.service.ts:processTranscription`; a `audio.processor.ts` deve ser uma casca fina que orquestra a fila e delega ao service. Greenfield (sem migração de dados).

---

## 1. Mapa das entities — AudioAsset vs IncidentAudioAsset

### 1.a — `AudioAsset`

- **Arquivo:** `src/modules/audio/entities/audio-asset.entity.ts:13`
- **Decorator:** `@Entity('incident_audio_assets')`
- **Index decorator:** `@Index('idx_audio_assets_incident', ['incidentId', 'chunkIndex'])`
- **Campos:**

| Propriedade | Coluna | Tipo |
|---|---|---|
| `id` | (default) | `uuid` PK |
| `incidentId` | `incident_id` | `uuid` |
| `chunkIndex` | `chunk_index` | `integer` |
| `durationSeconds` | `duration_seconds` | `double precision` |
| `storageKey` | `storage_key` | `varchar(500)` |
| `mimeType` | `mime_type` | `varchar(50)` default `'audio/webm'` |
| `sizeBytes` | `size_bytes` | `bigint` |
| `transcriptionStatus` | `transcription_status` | enum literal `['pending','processing','completed','failed']` default `'pending'` |
| `uploadedAt` | `uploaded_at` | `timestamptz` default `NOW()` |
| `createdAt` | `created_at` | `timestamptz` (`@CreateDateColumn`) |

- **Sem relação `@ManyToOne(Incident)`.**

**Quem grava (in production runtime):**
- `audio.service.ts:60-121 uploadChunk()` — `INSERT` via `repo.save(asset)` (linha 89). Chamado pelo controller em `POST /incidents/:id/audio`.
- `audio.service.ts:processTranscription()` chamaria `update(transcriptionStatus)` mas **nunca executa** (sem callers).

**Quem lê (in production runtime):**
- `audio.service.ts:130 listChunks()` — `repo.find({where:{incidentId}})`. Chamado em `GET /incidents/:id/audio`.
- `audio.service.ts:140 getDownloadUrl()` — `repo.findOne({where:{id:assetId}})`. Chamado em `GET /incidents/:id/audio/:assetId/download`.
- `audio.service.ts:60 uploadChunk` — `repo.findOne({where:{incidentId},order:{chunkIndex:'DESC'}})` para descobrir próximo chunkIndex.
- `admin.service.ts` (TypeORM via `IncidentAudioAsset`, ver abaixo) lê para o painel admin.

### 1.b — `IncidentAudioAsset`

- **Arquivo:** `src/modules/audio/entities/incident-audio-asset.entity.ts:19`
- **Decorator:** `@Entity('incident_audio_assets')` ← **MESMA TABELA QUE A v1**
- **Index decorator:** sem `@Index` próprio (depende do que TypeORM importar primeiro).
- **Campos:** todos idênticos à v1 acima. Diferenças:
  - `transcriptionStatus` declarado com `enum TranscriptionStatus { PENDING='pending', ... }` exportado (valores de string idênticos à v1).
  - **Tem relação extra:** `@ManyToOne(() => Incident, { eager: false }) @JoinColumn({ name: 'incident_id' }) incident: Incident;`

**Quem grava (in production runtime):** **ninguém.**
- `audio.processor.ts:48 update(transcriptionStatus='processing')` — código inerte (Bug #1).
- `audio.processor.ts:84 update(transcriptionStatus='completed')` — idem.
- `audio.processor.ts:104 update(transcriptionStatus='failed')` — idem.

**Quem lê (in production runtime):**
- `admin.service.ts` via `IncidentAudioAsset` repo (registrado em `admin.module.ts:8`) — para o painel admin (`getIncidentAudio`). Ler funciona porque é a mesma tabela. Apenas o campo `incident` (relação extra) só é populado se carregado com `relations: ['incident']`.

### 1.c — Schema SQL real em produção

`src/database/migrations/001_initial_schema.sql:208-221`:

```sql
CREATE TABLE incident_audio_assets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  incident_id UUID NOT NULL REFERENCES incidents(id),
  chunk_index INTEGER NOT NULL,
  duration_seconds DOUBLE PRECISION NOT NULL,
  storage_key VARCHAR(500) NOT NULL,
  mime_type VARCHAR(50) NOT NULL DEFAULT 'audio/webm',
  size_bytes BIGINT NOT NULL,
  transcription_status transcription_status NOT NULL DEFAULT 'pending',
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_audio_assets_incident ON incident_audio_assets(incident_id, chunk_index);
```

**Uma única tabela.** As duas classes mapeiam a mesma. Diferença com `IncidentLocation` do B2: aqui há uma FK explícita (`REFERENCES incidents(id)`) na migration, então a relação `@ManyToOne` da v2 é fiel ao schema — só não é usada pelo LocationService.

### 1.d — Diagnóstico do par

| Aspecto | v1 (`AudioAsset`) | v2 (`IncidentAudioAsset`) |
|---|---|---|
| Mesma tabela? | ✅ | ✅ |
| Mesma estrutura SQL? | ✅ | ✅ |
| Tem `@Index` declarado? | ✅ | ❌ |
| Tem `@ManyToOne(Incident)`? | ❌ | ✅ |
| Usado em runtime hoje? | ✅ (uploadChunk) | ❌ (processor inerte) |
| Usado por admin? | (depende — admin.module.ts importa) | ✅ |

**Conclusão:** mesmo cenário do `IncidentLocation` no B2. Hoje funciona "por sorte" (cada módulo registra a sua versão e elas não colidem porque o processor não roda). Vira problema na hora do fix.

---

## 2. Mapa das transcripts — `Transcript` vs `IncidentTranscript`

### 2.a — `Transcript`

- **Arquivo:** `src/modules/audio/entities/transcript.entity.ts:12`
- **Decorator:** `@Entity('incident_transcripts')`
- **Index decorators:** `@Index('idx_transcripts_incident', ['incidentId'])` + `@Index('idx_transcripts_audio', ['audioAssetId'])`
- **Campos:**

| Propriedade | Coluna | Tipo |
|---|---|---|
| `id` | (default) | `uuid` PK |
| `audioAssetId` | `audio_asset_id` | `uuid` |
| `incidentId` | `incident_id` | `uuid` |
| `text` | (default) | `text` |
| `confidence` | (default) | `double precision` default `0` |
| `language` | (default) | `varchar(10)` default `'en'` |
| `distressSignals` | `distress_signals` | `jsonb` default `'[]'` |
| `aiSummary` | `ai_summary` | `text` nullable |
| `aiRiskIndicators` | `ai_risk_indicators` | `jsonb` nullable default `'[]'` |
| `createdAt` | `created_at` | `timestamptz` (`@CreateDateColumn`) |

- **Sem relações.**

**Quem grava:** **ninguém em runtime.** `audio.service.ts:processTranscription:268 transcriptRepo.save(transcript)` — código inerte (sem callers).

**Quem lê:** `audio.service.ts:182 getTranscripts()` — `repo.find({where:{incidentId}})`. Chamado em `GET /incidents/:id/transcripts`. **Sempre retorna `[]` em produção.**

### 2.b — `IncidentTranscript`

- **Arquivo:** `src/modules/audio/entities/incident-transcript.entity.ts:13`
- **Decorator:** `@Entity('incident_transcripts')` ← **MESMA TABELA QUE A v1**
- **Sem `@Index` declarados.**
- **Campos:** idênticos à v1.
- **Relações extras:** `@ManyToOne(IncidentAudioAsset)` e `@ManyToOne(Incident)`.

**Quem grava:** **ninguém em runtime.** `audio.processor.ts:71-81 transcriptRepo.save(transcript)` — código inerte (Bug #1).

**Quem lê:** `admin.service.ts` (via `IncidentTranscript` registrado em `admin.module.ts:9`) para painel admin.

### 2.c — Schema SQL real em produção

`src/database/migrations/001_initial_schema.sql:227-241`:

```sql
CREATE TABLE incident_transcripts (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  audio_asset_id UUID NOT NULL REFERENCES incident_audio_assets(id),
  incident_id UUID NOT NULL REFERENCES incidents(id),
  text TEXT NOT NULL,
  confidence DOUBLE PRECISION NOT NULL DEFAULT 0,
  language VARCHAR(10) NOT NULL DEFAULT 'en',
  distress_signals JSONB NOT NULL DEFAULT '[]',
  ai_summary TEXT,
  ai_risk_indicators JSONB DEFAULT '[]',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX idx_transcripts_incident ON incident_transcripts(incident_id);
CREATE INDEX idx_transcripts_audio ON incident_transcripts(audio_asset_id);
```

**Uma única tabela.** Mesmo padrão do par anterior.

---

## 3. Quem grava o quê HOJE (estado real em produção)

### Confirmação empírica (Henrique, 28/04 ~03:50)

#### Postgres prod

```
incident_audio_assets:
  1 row total
  id: 2a4628ce-42ff-48f5-a82f-a256b6ef1998
  incident_id: f93fb183-2f8d-4dd4-90c5-f01f4569c6dd
  uploaded_at: 2026-04-28 02:13:25
  transcription_status: 'pending'  ← preso há ~1h40min
  size_bytes: 1920

incident_transcripts:
  0 rows total  ← ZERO desde o início do projeto
```

#### Redis prod

```
bull:audio-processing:wait      → list com 1 job aguardando
bull:audio-processing:1         → o job (TTL=-1, nunca expira)
bull:audio-processing:meta      → existe (queue criada pelo producer)
bull:audio-processing:events    → stream existe
bull:audio-processing:marker    → existe
bull:audio-processing:id        → existe

bull:audio-processing:active    → AUSENTE
bull:audio-processing:stalled-check → AUSENTE  ← sem worker rodando heartbeat
```

**Comparativo (mesmo Redis, filas que funcionam):**
```
bull:alert-dispatch:1, :4..:12  → jobs processados
bull:alert-dispatch:stalled-check → TTL ativo (worker rodando)
bull:alert-dispatch:failed      → zset (DLQ ativa)
bull:journey-expiry:stalled-check → TTL=14 (worker rodando)
```

**Conclusão empírica:** `alert-dispatch` e `journey-expiry` rodam normalmente. **`audio-processing` é a única fila com producer enfileirando e zero consumers.** O job sobe ao Redis e fica órfão indefinidamente.

### Tradução para a pergunta original do briefing

> O áudio do nosso teste do R2 — o que foi gravado em qual tabela?

- **Tabela `incident_audio_assets`:** 1 row (o do teste). Gravada via classe `AudioAsset` (`audio.service.ts:uploadChunk`).
- **Tabela `incident_transcripts`:** 0 rows. Tabela está vazia desde o deploy. **Nenhum áudio jamais foi transcrito.**
- **Não existe** "tabela com prefixo audio" separada de "tabela com prefixo incident_audio". Existe **uma única tabela**, e a duplicação é só de classe TypeScript.

---

## 4. Fluxo real do upload (audit do código)

### 4.a — Caminho do producer (executa em produção ✅)

```
POST /incidents/:id/audio
  ↓
audio.controller.ts:48 uploadChunk()
  ↓ valida MIME, file size, duration
audio.service.ts:60 uploadChunk(incidentId, userId, file, durationSeconds)
  ↓ assertOwnership (B2)
  ↓ calcula chunkIndex (último chunk + 1)
  ↓ uploadToS3(buffer)                            ← áudio vai pro R2
  ↓ audioAssetRepo.create + save                   ← INSERT em incident_audio_assets
  ↓                                                 (via classe AudioAsset, status='pending')
  ↓ createIncidentEvent('audio_chunk_uploaded')   ← INSERT em incident_events
  ↓ audioQueue.add('transcribe', payload)         ← enqueue em queue 'audio-processing'
  ↓ retorna 201 com asset metadata
FIM DO PRODUCER
```

Configuração da queue do producer:
- `audio.module.ts:18` — `BullModule.registerQueue({ name: 'audio-processing' })`
- `audio.service.ts:30` — `@InjectQueue('audio-processing')`
- `audio.service.ts:107` — `audioQueue.add('transcribe', { audioAssetId, incidentId, storageKey, mimeType }, { attempts: 3, backoff: exponential 5000ms, removeOnComplete: true })`

### 4.b — Caminho do consumer (NÃO executa em produção ❌)

```
[NUNCA ATIVADO]
audio.processor.ts:41 process(job)
  ↓ audioAssetRepo.update(transcriptionStatus='processing')  ← via IncidentAudioAsset
  ↓ downloadFromS3(storageKey)
  ↓ transcribe(buffer, language)                              ← TODO placeholder
  ↓ analyzeDistressSignals(text)                              ← TODO placeholder (vazio)
  ↓ transcriptRepo.create + save                              ← INSERT em incident_transcripts
  ↓                                                            (via classe IncidentTranscript)
  ↓ audioAssetRepo.update(transcriptionStatus='completed')
  ↓ incidentGateway.broadcastTimelineEvent('transcription_completed', ...)
FIM DO CONSUMER (teórico)
```

**Por que não executa:**

1. **Bug #1** — `AudioProcessor` não está em `providers: [...]` de nenhum módulo:
   ```
   src/modules/journey/journey.module.ts:23      providers: [JourneyService, JourneyExpiryProcessor],   ✅
   src/modules/notifications/notifications.module.ts:26 providers: [..., AlertDispatchProcessor],         ✅
   src/modules/audio/audio.module.ts:25          providers: [AudioService, DeepgramProvider, AiClassifierProvider],
                                                                                                       ↑
                                                                                          AudioProcessor AUSENTE
   ```

2. **Bug #2** — mesmo se registrado, o decorator `@Processor('audio')` (audio.processor.ts:19) pega a fila errada. Producer enfileira em `'audio-processing'`. Worker escutaria `'audio'`.

### 4.c — São dois mundos paralelos OU mesmo mundo?

**Mesmo mundo, com duas classes ociosas tocando a mesma tabela.**

- `incident_audio_assets` (tabela única) é manipulada SOMENTE pela classe `AudioAsset` em runtime de produção.
- `incident_transcripts` (tabela única) **nunca é manipulada** em runtime.
- A classe `IncidentAudioAsset` está registrada em `admin.module.ts` para queries do painel admin — então **é usada para LEITURA**, mas nunca para escrita.
- A classe `IncidentTranscript` idem.

A duplicação só vai morder na hora de juntar os módulos em escopo de DI compartilhado (Bug #3 vira hard blocker).

---

## 5. Por que há divergência

### 5.a — Hipóteses do briefing

- **(a) Refactor incompleto** — alguém renomeou Audio* → IncidentAudio* mas só atualizou parte do código. ✅ **Compatível com a evidência.**
- **(b) Duas implementações concorrentes** — devs em paralelo. ❌ Refutada.
- **(c) Dead code intencional** — processTranscription como "futuro" ou processor como "antigo". ❌ Refutada.
- **(d) Outro** — combinação de (a) + boilerplate copiado. ✅ Possível.

### 5.b — Evidência do git blame

```
$ git log --all --oneline --follow src/queue/audio.processor.ts
3f547a6 Initial commit - SafeCircle pilot ready

$ git log --all --oneline --follow src/modules/audio/audio.service.ts
02fd788 fix(security): close IDOR in audio endpoints (B2 — partial)
3f547a6 Initial commit - SafeCircle pilot ready
```

**Os 3 bugs nasceram juntos no commit único `3f547a6`** (Henrique, 2026-04-07). O `audio.service.ts` só foi tocado depois pelo B2 (que não modificou nada do pipeline de transcrição — só validação de ownership).

### 5.c — Hipótese refinada

A hipótese mais consistente com a evidência:

> Um boilerplate / scaffold de pipeline foi colocado no initial commit, com **dois caminhos esboçados** que nunca foram terminados de unificar:
>
> - O **service path** (Deepgram + AiClassifier providers reais wired, mas órfão de caller).
> - O **worker path** (placeholder com TODO, esquecido o registro no módulo, esquecido o nome certo da queue).
>
> Algum dos dois caminhos era para ter sido descartado ou conectado ao outro, e isso ficou pra "depois". O "pilot ready" do commit message é otimista demais — não estava ready, só compilava.

Não há evidência de mau intento, é um vazio de finalização. Coerente com a quantidade de TODOs/placeholders já documentados no relatório de auditoria (`docs/AUDITORIA_2026-04-28.md`).

---

## 6. Recomendação técnica

### Confirmação: **Abordagem A — Worker chama o service.**

**Justificativa:**

1. **Lógica de domínio já existe em `audio.service.ts:processTranscription`** (linhas 213-323): Deepgram wired, AiClassifier wired, gerenciamento de status, eventos de incidente, classificação de distress, criação de `transcript` com `aiRiskIndicators`. É o caminho **completo**.

2. **`audio.processor.ts:transcribe/analyzeDistressSignals`** retorna placeholder vazio. Eliminação direta.

3. **Worker é orquestrador, service é onde lógica vive.** Mover Deepgram + AiClassifier para o processor (Abordagem B) inverteria a hierarquia idiomática NestJS.

4. **Greenfield (zero transcripts existentes)** — sem migração de dados.

5. **Padrão DRY mantido.** Outros workers (`alert-dispatch.processor.ts`, `journey-expiry.processor.ts`) seguem o padrão "processor → service". Ficar consistente.

### Sequência proposta de fixes (commits separados, na ordem)

#### Fix 1 — Consolidar entities duplicadas (mesmo padrão do B2 location)

**Antes** de qualquer wire-up novo, eliminar a duplicação. Razão: assim que o `AudioModule` exportar `AudioService` para uso por um processor que importe `IncidentsModule` indiretamente, vamos cair no mesmo conflito de TypeORM metadata que tivemos no B2.

- Comparar `AudioAsset` vs `IncidentAudioAsset` campo a campo (já feito acima — diferença é o `@ManyToOne(Incident)` extra na v2 e o `@Index` extra na v1).
- Escolher canonical. **Recomendação:** **v2 (`IncidentAudioAsset`)** como canonical, porque (a) tem a relação com `Incident` que pode ser útil para joins futuros e (b) o nome reflete melhor a tabela `incident_audio_assets`. Adicionar o `@Index` que falta. Renomear classe para `IncidentAudioAsset` (manter o nome) e exportar do mesmo arquivo, eliminando `audio-asset.entity.ts`.
- Idem para `Transcript` vs `IncidentTranscript`. Canonical v2, eliminar v1.
- Atualizar todos os imports (audio.service.ts, audio.processor.ts, admin.module.ts, audio.module.ts).
- **Esforço:** 30-45 min. **Risco:** baixo. Schema SQL idêntico (synchronize:false). Build TypeScript pega o que faltou.

#### Fix 2 — Registrar `AudioProcessor` no `AudioModule`

```diff
 // audio.module.ts
+import { AudioProcessor } from '../../queue/audio.processor';
 ...
 @Module({
   ...
   providers: [
     AudioService,
     DeepgramProvider,
     AiClassifierProvider,
+    AudioProcessor,
   ],
   ...
 })
```

- **Cuidado:** AudioProcessor injeta `IncidentGateway` (audio.processor.ts:33). Se IncidentGateway não estiver disponível no escopo do AudioModule, vai dar erro de DI. Verificar na hora.
- **Esforço:** 10 min. **Risco:** baixo (modulo o IncidentGateway).

#### Fix 3 — Alinhar nome da queue

Sugestão: manter `'audio-processing'` (já está no producer e em uso). Mudar o decorator no processor:

```diff
 // audio.processor.ts
-@Processor('audio', { concurrency: 3 })
+@Processor('audio-processing', { concurrency: 3 })
```

- **Esforço:** 1 min. **Risco:** zero.

#### Fix 4 — Worker delega ao service

```diff
 // audio.processor.ts
 async process(job) {
-  // ... 100 linhas de lógica com TODOs e placeholder ...
+  await this.audioService.processTranscription(job.data);
 }
```

- Injetar `AudioService` no constructor do `AudioProcessor`.
- Remover `transcribe()` e `analyzeDistressSignals()` placeholders.
- Remover `S3Client`, `IncidentAudioAssetRepo`, `IncidentTranscriptRepo` do processor — tudo isso já está no service.
- O `IncidentGateway.broadcastTimelineEvent('transcription_completed')` que hoje está no processor deveria migrar para o service também (consistência: service emite os eventos de domínio, processor só orquestra a fila). **Mas** isso pode ser um sub-passo: primeiro fazer o delegate funcionar, depois migrar o broadcast.
- **Esforço:** 30-60 min. **Risco:** médio (precisa testar end-to-end com Deepgram real ou stub).

#### Fix 5 — Remover `@deprecated` de `processTranscription`

Quando virar caller real (via processor), o JSDoc fica obsoleto. Atualizar a docstring para descrever o novo papel.

- Bonus: remover entry `processTranscription órfão` do `docs/DEBITOS_TECNICOS.md` (item registrado no commit `7e4d54a` durante o B2). Item resolvido.

#### Fix 6 — Testes

Como o B2 mostrou, testes integration neste projeto são unit-style com mocks. Specs propostos:

- `test/integration/audio-pipeline.spec.ts`:
  - Service `processTranscription` → mockar Deepgram e AiClassifier; verificar que transcript é gravado com signals e aiSummary corretos.
  - Worker delegate → mockar `audioService.processTranscription`; chamar `processor.process(job)`; verificar que delegate foi chamado com o payload exato do job.
  - Status transitions → `'pending' → 'processing' → 'completed'` ao longo do pipeline.
  - Failure path → mock que lança no Deepgram → verificar `transcriptionStatus='failed'` e re-throw para BullMQ retry.

- **Cobertura mínima desejada:** todos os 6 caminhos do `processTranscription` (sucesso, no speech detected, distress detectado, distress não detectado, erro de Deepgram, erro de AiClassifier).

- **Esforço:** 2-3h.

#### Esforço total estimado

**4-6 horas**, alinhado com o B2 em ordem de complexidade.

### Checkpoints obrigatórios antes de cada fix (regra do B2)

1. **`npm test` baseline** — confirmar 120/120 antes de cada commit.
2. **`nest build`** — confirmar zero warnings TS.
3. **Mostrar diff** antes do commit. Aguardar aprovação.
4. **Sem push** até toda a sequência estar verde.

### Riscos não-cobertos pelo plano

- **Custo financeiro pós-fix:** Deepgram Nova-2 ~$0.0043/min. OpenAI gpt-4o classifier ~$5/1M tokens input. Se um abuser fizer upload massivo de áudio, custo descontrolado. **Recomendação:** rate limit por user.id na queue (não no controller, que é `@SkipThrottle` de propósito) **antes** de habilitar em prod. Pode ser ticket separado.
- **Dados retroativos:** atualmente 1 áudio com `pending` há ~1h40min. Após o fix, decidir: reprocessar (re-enqueue) ou marcar como `failed_legacy`. **Recomendação:** reprocessar — o áudio está íntegro no R2.

---

## 7. Bug latente — provedores em produção

### 7.a — Callers de Deepgram e AiClassifier

Confirmado por `grep -rn`:
- `DeepgramProvider.transcribe`: chamado SOMENTE em `audio.service.ts:233` (dentro do `processTranscription` órfão).
- `AiClassifierProvider.classifyDistress`: chamado SOMENTE em `audio.service.ts:247` (idem).
- Os dois são providers em `audio.module.ts:25` — instanciados em runtime (NestJS DI roda construtor), mas nenhum método é invocado.

### 7.b — Custo financeiro hoje

- **Deepgram:** $0/mês. Charge-per-use, zero requests = zero billing.
- **OpenAI:** $0/mês. Charge-per-token.

### 7.c — Custo após fix (atenção)

- **Deepgram Nova-2:** ~$0.0043 por minuto de áudio.
  - Cenário típico (chunks de 30s, 1 incident = 5 chunks = 2.5 min): ~$0.011 por incident.
  - 100 incidents/dia = ~$33/mês.
  - 1000 incidents/dia (escala governo) = ~$330/mês.
- **OpenAI gpt-4o classifier:** ~$5/M tokens input, ~$15/M tokens output.
  - Chunk de 30s ≈ ~80-150 palavras transcritas = ~200 tokens input + ~50 tokens output classifier = ~$0.0014 por chunk.
  - 100 incidents/dia × 5 chunks = $0.7/dia = $21/mês.
  - 1000 incidents/dia = $210/mês.

**Total estimado pós-fix:** $54-540/mês dependendo de escala. **Sem cap, viável em piloto. Em escala governo, exigir hard cap por incident e por billing period.**

---

## 8. Riscos não-óbvios

### 8.a — Risk engine consume transcript text? **Sim, parcialmente — e tem bug adicional.**

`src/modules/risk-engine/risk-rules.config.ts` define duas regras que dependem de signals derivados de áudio:

```ts
{
  id: 'audio_distress_detected',
  signalType: 'audio_distress_detected',
  scoreDelta: 25,                              // sobe risk score em 25 pontos
  reason: 'Audio analysis detected distress signals',
}
{
  id: 'help_phrase_detected',
  signalType: 'help_phrase_detected',
  scoreDelta: 35,                              // sobe risk score em 35 pontos
  reason: 'Voice transcription detected a help/distress phrase',
}
```

**Mas:** `grep -rn "audio_distress_detected\|help_phrase_detected"` em `src/` — **zero callers que emitem esses signals.** As regras existem, mas ninguém dispara `processRiskSignal({type: 'audio_distress_detected', ...})`.

`processTranscription` no service (`audio.service.ts:213-323`) chama `createIncidentEvent('transcription_completed')` e `createIncidentEvent('ai_analysis_result')` quando há distress, mas **NÃO emite signal para o risk engine**. Falta um wire entre `aiClassifier.classifyDistress(text)` retornar `isDistress=true` e chamar `incidentsService.processRiskSignal(incidentId, userId, { type: 'audio_distress_detected', payload })`.

**Implicação:** mesmo após corrigir os 3 bugs principais, o **risk score nunca subirá com base no áudio**. Os signals de áudio são a 2ª e 3ª regra de maior peso (+25 e +35), atrás apenas de coerção (+95). Sem isso, risk engine perde uma das vias mais importantes de detecção em violência doméstica.

**Recomendação:** adicionar um Fix 4.5 ao plano — depois que `processTranscription` estiver wired ao processor, fazer o classifier emitir os signals corretos. Pequeno (5-10 linhas), mas crítico.

### 8.b — WebSocket eventos `transcription_completed`

`incident.gateway.ts:157 broadcastTimelineEvent` é o método genérico. É chamado em:
- `audio.processor.ts:89` — código inerte (Bug #1).

Se buscarmos por `transcription_completed` literal:
- Definido como literal de string em `audio.processor.ts:90` (inerte).
- Definido como literal em `audio.service.ts:276` dentro de `createIncidentEvent` (cria registro em `incident_events`, mas isso não é um broadcast WebSocket — é um row no DB).

**Impacto hoje:** contatos no portal nunca veem evento timeline `transcription_completed`. Após o fix, dependendo da escolha (broadcast no service vs no processor), começam a ver.

**Recomendação:** mover o `broadcastTimelineEvent` para dentro do `processTranscription` no service (consistência: domain emite eventos de domínio). Processor só atualiza progresso da fila.

### 8.c — Audit log

`AuditService.log` é chamado explicitamente em pontos específicos (`admin.controller.ts:147`). O `AuditInterceptor` (`audit.interceptor.ts`) loga em winston, não persiste no DB.

Hoje, como o worker não roda:
- Job acumulando no Redis: **sem audit**.
- Status `pending` perpétuo: **sem audit**.
- Nenhum sinal externo de que algo está errado.

Após o fix:
- Sucesso de transcrição → `incident_events` row (já feito pelo service).
- Falha de Deepgram/OpenAI → log winston + retry BullMQ.
- **Recomendação:** adicionar `auditService.log({ action: 'transcription.completed', resource: 'audio_asset', resourceId: assetId, ... })` no service, com `correlation_id` propagado da request original.

### 8.d — Migração / dado retroativo

1 áudio com `transcription_status='pending'` há ~1h40min. Em prod, podem existir mais (depende de testes feitos antes de hoje). **Plano simples:**

```sql
-- Listar candidatos:
SELECT id, incident_id, uploaded_at, storage_key
FROM incident_audio_assets
WHERE transcription_status = 'pending'
ORDER BY uploaded_at ASC;

-- Re-enqueue cada um na fila 'audio-processing'.
-- Pode ser script ad-hoc ou endpoint admin protegido.
```

**Cuidado:** se o número for alto e Deepgram cobrar por lote, dimensionar o batch. Para 1 áudio, irrelevante.

### 8.e — Outros bugs descobertos durante a investigação

1. **Risk engine não recebe signals de áudio** — ver 8.a. Bug adicional ao plano original.
2. **`uploadChunk` enfileira job mesmo se `audioConsent` for `'none'`** — não verifiquei a fundo, mas vale confirmar que `audio.service.ts:uploadChunk` respeita o setting `audioConsent` da `emergency_settings`. Se não respeitar, está gravando áudio mesmo quando a usuária optou por não consentir. Possível violação LGPD. **Não auditei a fundo, mas recomendo investigar.**
3. **`DeepgramProvider` em "stub mode" se `DEEPGRAM_API_KEY` ausente** (ver `docs/AUDITORIA_2026-04-28.md` item 1.3). Combinado com o pipeline quebrado, é dois níveis de "fingir que funciona". Se o user configura o API key e ativa o pipeline, deve verificar que `LIVE` mode realmente está ativo via `/health/pilot`.

---

## 9. Notas operacionais

### 9.a — Sobre o token Railway compartilhado

Henrique compartilhou na conversação um token Railway (`8b5cc117-...`). **Não persisti em nenhum arquivo deste relatório nem em código.** Se precisar de acesso via Railway CLI numa rodada futura, o token deve ser passado on-demand e não logado.

### 9.b — Comparação com o B2

Este caso e o B2 têm muito em comum:
- Ambos descobriram entity duplicada que era bug latente.
- Ambos exigiram refactor "fora do escopo" para destravar o fix principal.
- Ambos têm origem no initial commit (3f547a6).

**Padrão recorrente:** o initial commit deixou várias inconsistências estruturais. Vale considerar uma sweep dedicada após este fix ("varredura de boilerplate incompleto"), procurando outros pares de entities duplicadas / workers não registrados / queue names divergentes.

Procurar por:
- `grep -rn "@Processor(" src/queue/` vs `grep -rn "@InjectQueue(" src/` — confirmar match.
- `grep -rn "@Entity('" src/` agrupando por nome de tabela — encontrar duplicatas.
- `grep -rn "providers: \[" src/**/*.module.ts` — confirmar que toda classe `@Injectable()` que não é guard/interceptor está em algum providers.

---

## 10. Resumo da decisão

**Pipeline de transcrição/análise de áudio em produção: 0% funcional.** Causa: 3 bugs estruturais sobrepostos no initial commit.

**Caminho recomendado:** Abordagem A (worker chama service), com 6 fixes em sequência + tratamento do bug adicional do risk engine não consumir signals.

**Esforço:** 4-6h de trabalho técnico + alinhamento sobre custo de Deepgram/OpenAI antes de habilitar em prod.

**Bloqueadores residuais antes de implementar:**
- ✅ Confirmação empírica: já obtida.
- 🟡 Decidir custo cap pós-fix (rate limit + billing alert).
- 🟡 Decidir destino do 1 áudio `pending` existente (re-enqueue ou abandonar).
- 🟡 Decidir se 8.a (risk engine signals) entra no mesmo PR ou vai para PR separado.

Aguardando aprovação do plano de fix.
