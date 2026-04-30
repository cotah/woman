# SafeCircle — Roadmap Consolidado

**Criado em:** 2026-04-30
**Versão:** 1.0
**Substitui:** `SafeCircle_Roadmap.docx` (11/Abril/2026), severamente desatualizado conforme auditoria do mobile-app descobriu

Este documento é a **fonte única de verdade** do estado do projeto. Linguagem simples — serve pra dev novo entrando no projeto, pra você daqui 6 meses, e potencialmente pro tio na PF ou pra um advogado. Honesto sobre o que está pronto e sobre o que falta.

---

## 1. O que é SafeCircle

SafeCircle é um app de segurança pessoal pra mulheres em situação de risco de violência doméstica. **Detecta automaticamente** sinais de emergência (palavra de socorro falada, padrão de movimento, geofence) e **aciona ajuda sem a usuária precisar fazer nada visível pro agressor** — contatos de confiança recebem SMS, push e ligação com sua localização em tempo real.

**Diferencial central:** o app foi desenhado pra continuar funcionando mesmo se o agressor tomar o celular. Tem PIN de coação (digitar "cancela" numa tela falsa enquanto o backend secretamente escala), modo disfarce (calculadora funcional que esconde o app real), gravação de áudio em chunks que sobe pra nuvem antes que o aparelho possa ser desligado, tracking 24/7 em background que sobrevive a reboot.

---

## 2. Modelo de Negócio (Resumo)

Confirmado pelo Henrique em sessões anteriores:

- **Plataforma:** mobile (Flutter, Android + iOS). Frontend web é apenas painel auxiliar.
- **Pricing previsto:** R$ 14,99/mês (BR) e € 3,99/mês (EU)
- **Free tier:** existirá, com limites (ex: 30 transcripts/mês, jornadas curtas). Detalhe pendente.
- **Regra inegociável:** features de emergência **NUNCA atrás de paywall**. SOS, contatos, push, gravação — sempre grátis.
- **Cronograma de monetização:** **NÃO monetizar** nos primeiros 6-12 meses. Foco em base de usuárias e casos de impacto documentados.
- **Vetor B2G:** licitação governamental brasileira via tio na Polícia Federal. Sem deadline rígido — só apresenta "quando 100% pronto e funcionando".

---

## 3. Estado Atual

### 3.1 Backend — Estado: **Excelente**

| Aspecto | Status |
|---|---|
| Funcional em produção | ✅ Validado end-to-end (Railway) |
| Pipeline de áudio (Deepgram + OpenAI + Risk Engine) | ✅ Testado com fala real, ~99% acurácia (Bug 8.a) |
| Bug 8.a (risk score escalando) | ✅ Validado em prod: 70 → 100 em 6s |
| Infraestrutura | ✅ Postgres + Redis + R2 + Sentry — tudo cloud, monitorado |
| Testes automatizados | ✅ 131/131 passando |
| Lint | ✅ 0 errors, 0 warnings (sweep B fechado em 2026-04-30) |
| Build | ✅ Limpo |
| **Débitos técnicos ativos** | **0** |
| Decisões arquiteturais documentadas | 1 (mocks `: any` em `test/` — convenção idiomática Jest+NestJS, suprimida via override ESLint específico) |
| Débitos resolvidos no histórico | 9 |

**Trabalho recente que fechou o ciclo:**
- Audio pipeline retry duplica side effects → resolvido com 3 camadas (UNIQUE constraint, pre-check, catch defensivo)
- Lint baseline 149 warnings → 0 (4 PRs no src/ + 1 override consciente em test/)
- JwtAuthGuard duplicado (bug latente de segurança em `@Public`) → resolvido
- Convenção `@Req` vs `@CurrentUser` → alinhada

Backend não tem trabalho prioritário pendente.

### 3.2 Mobile — Estado: **Avançado mas com gaps críticos**

Auditoria completa registrada em [`docs/AUDITORIA_FLUTTER_2026-04-30.md`](AUDITORIA_FLUTTER_2026-04-30.md). 22 findings catalogados.

**Estado preliminar:** ~80-85% funcional. Mas tem **3 bloqueadores absolutos** que precisam ser resolvidos antes de qualquer demo.

#### 3 Bloqueadores absolutos

1. **🚨 Build Android quebrado** (finding #22) — `flutter_local_notifications` v17+ exige `coreLibraryDesugaringEnabled = true` em `build.gradle.kts`. App **NÃO compila nem em debug** com a config atual. Fix é 5 linhas. **Sem isso, nada funciona em Android — nenhum teste, nenhum APK, nenhuma demo.**
2. **Push remoto FCM** (findings #1, #7, #9, #16, #17) — `firebase_messaging` ausente do `pubspec.yaml`, `google-services.json` e `GoogleService-Info.plist` ausentes. Backend envia FCM, app não tem como receber. Quebra: notificar contatos quando app fechado, Safe Journey check-in, FCM token registration.
3. **IncidentDetailScreen é STUB** (finding #13) — mostra mock hardcoded ("Marie Dupont", "Lucas Martin"), não chama backend. Usuária verá dados falsos ao clicar em qualquer incident detail. Bloqueador absoluto pra demo.

#### 3 Gaps funcionais críticos (alguns afetam demo, outros bloqueiam MVP público — vide §4.2 e §5.1 para classificação por horizonte)

1. **Voice biometrics** (finding #2) **[Horizonte 1, vide §4.2]** — onboarding promete "learn your unique voice pattern" e coleta 3 gravações, mas o serviço de detecção **nunca usa as gravações**. Matching é puramente Levenshtein de texto reconhecido com threshold 70% — qualquer voz que diga a palavra dispara. Falsos positivos por TV, crianças, agressor falando próximo são reais. **UI mente sobre o comportamento.**
2. **Calculator screen sem rota** (finding #8) **[Horizonte 1, vide §4.2]** — modo disfarce está 100% codado e funcional (detecta PIN no digit sequence, navega `/home` quando PIN bate), mas não tem rota no router. **Usuária não consegue acessar a feature.**
3. **Delete account é só logout** (finding #14) **[Horizonte 2, LGPD blocker]** — `privacy_screen.dart:327` tem FIXME explícito. Apenas faz logout. **Bloqueador LGPD** — direito de exclusão não está cumprido. Não afeta demo PF (§4) — afeta publicação pública (§5.1).

#### O que está bem

- Backend integration: industry-grade. JWT refresh com race guards, retry com backoff exponencial, dual auth header+query no WebSocket, todos os 6 eventos do `IncidentGateway` wireados.
- Native code: 3 arquivos Kotlin (MainActivity, ForegroundService com WakeLock+START_STICKY+onTaskRemoved, BootReceiver) + Swift (SilentSpeechRecognizer pra zero-ding iOS). Trabalho que costuma demorar num app Flutter sério, está completo.
- Features avançadas funcionais: coercion handler com secret-cancel pattern, always-on tracking 24/7, geofencing com auto-zones a partir de learned places (mas só local), test mode que bypassa Twilio no backend, voice activation nativa iOS silenciosa.
- Sem hardcoded credentials.
- 23 rotas configuradas, 18 services injetados, organização clara `core/` + `features/`.
- `flutter analyze`: 72 issues (1 error de boilerplate de teste, 9 warnings, 62 infos cosméticos) — saúde do código mobile é boa, sweep similar ao backend possível em 1-2h.

### 3.3 O que NÃO existe ainda

Funcionalidades que aparecem em conversas/feedback/roadmap mas **não foram implementadas**:

- Painel administrativo / dashboard de operadora (pra atender chamados 24/7)
- Integração formal com PF / órgãos públicos (apenas mencionada como vetor B2G)
- Sistema de pagamentos (cobrança recorrente, free tier limits)
- Audit log persistente em banco (Wave 2 / B10)
- Hard delete LGPD (Wave 2 / B7)
- Fila offline (Wave 2 / B5) — quando app perde internet, queues cliente-side antes de sync
- Confirmação visual de entrega de SOS (Wave 2 / B8) — usuária ver "SMS chegou em X às Y"
- Voice biometrics (TFLite + speaker verification)
- Botão físico pra acionar SOS sem abrir app (3× lock screen / 4× volume baixo) — pedido por usuária em pesquisa
- Pesquisa formal com 20+ mulheres consolidada (FEEDBACK_USUARIAS.md tem só 1 entry registrada)

---

## 4. Horizonte 1 — Demo na PF

**Objetivo:** ter app rodando ponta-a-ponta pra apresentar ao tio na Polícia Federal. **Não é produto público** — é proof-of-concept funcional pra ancorar conversa B2G.

**Estimativa total:** 2-3 semanas de trabalho focado.

### 4.1 P0 ABSOLUTO — Sem isso, nada funciona

| Item | Esforço | Status atual | Detalhe |
|---|---|---|---|
| Build Android desugaring | **5 min** | Não fixado | 5 linhas em `android/app/build.gradle.kts` (`isCoreLibraryDesugaringEnabled = true` + dependency `desugar_jdk_libs:2.1.4`). Sem isso, app não compila nem em debug. |
| `ENVIRONMENT=staging` como default em mobile | 30 min | Default = `dev` | Mudar default em `main.dart:52` OU sempre passar `--dart-define=ENVIRONMENT=staging` em build script. Sem isso, build release aponta pra `localhost:3000` silenciosamente. |

**Total P0 absoluto: ~35 minutos.** É trivial mas bloqueia tudo.

### 4.2 P0 — Demo Blockers

| Item | Esforço | Status atual | Detalhe |
|---|---|---|---|
| IncidentDetailScreen real (não mock) | 1-2 dias | Stub com mock hardcoded | Wire pra backend usando `incidentService.getIncident(id)` e `getTimeline(id)` que já existem. Sem isso, demo expõe dados falsos. |
| Push remoto FCM completo | 2-3 dias | Não existe | (1) Adicionar `firebase_messaging` ao pubspec.yaml, (2) criar projeto Firebase, (3) baixar configs (`google-services.json`, `GoogleService-Info.plist`), (4) implementar token registration no app, (5) criar endpoint backend `/users/me/devices` (atualmente declarado em `api_endpoints.dart` mas backend não tem). Sem isso, contatos não recebem push se app estiver fechado. |
| Calculator screen com rota | 30 min - 2 h | Code pronto, sem rota | Decisão de produto pendente (vide §7.2). Recomendação preliminar: setting "Stealth Mode" liga/desliga, troca tela inicial via launcher trick OU navigation guard. |
| Voice biometrics decidido | 1 dia (UI) ou 3-5 dias (impl) | Promessa quebrada | Decisão de produto pendente (vide §7.1). Recomendação preliminar: opção B (UI honesta) pra Horizonte 1, A (implementar) pra Horizonte 2 ou 3. |

**Total P0 demo blockers: 4-9 dias.**

### 4.3 P1 — Polish da demo

| Item | Esforço | Status atual | Detalhe |
|---|---|---|---|
| E2E test de SOS real (Twilio + FCM rodando) | 2-3 h | Nunca foi testado em prod com SMS chegando | Criar incident teste, ver SMS chegar de verdade no telefone do contato, ver push no aparelho do contato. Inclui validar Twilio account ativa + FCM project ativo. |
| Bug coercion mode sync (#3) | 30 min | Conhecido | Setar `_isCoercionMode = true` ANTES da `await api.post(cancel)` em `incident_service.dart:159-178`. Em rede ruim hoje, UI vai pra coercion screen mas IncidentService flag fica errado. |
| Audio retry de upload (#12) | 2-3 h | Sem retry | `audio_service.dart:147` — quando upload falha, arquivo fica local mas sem nova tentativa. Adicionar retry exponencial OU job persistido pra retry quando rede voltar. |
| Lint cleanup mobile (parcial — só errors + warnings) | 1-2 h | 1 error + 9 warnings + 62 infos | Cobrir só os errors+warnings (10 itens) pra pre-flight. Os 62 infos cosméticos podem ficar pra Horizonte 2. |

**Total P1 polish: 1 dia.**

### 4.4 Outputs do Horizonte 1

Ao final, deve estar entregue:

- ✅ App buildando em Android (APK funcional, instalável em celular real)
- ✅ Pipeline ponta-a-ponta funcionando: SOS botão → backend cria incident → countdown → activate → Twilio SMS chega de verdade no contato + Firebase Push chega no app dele
- ✅ Demo script de 5-10 minutos pra apresentar (cenário roteirizado: instalar app → onboarding → triggar SOS → mostrar SMS chegando → mostrar tracking ao vivo)
- ✅ Sem mocks visíveis ao usuário (incident detail mostra dados reais)
- ✅ Modo disfarce (Calculator) acessível por algum caminho na UI
- ✅ Voice activation com UI honesta (sem promessa de biometrics que não existe)

---

## 5. Horizonte 2 — MVP público

**Objetivo:** lançar nas lojas pra primeiras usuárias reais. **NÃO é versão final** — é versão "lançável legal", com tudo que protege o projeto juridicamente e dá experiência aceitável (sem ser feature-complete).

**Estimativa total:** +6-10 semanas após Horizonte 1.

### 5.1 Bloqueadores Legais

| Item | Esforço | Status atual | Detalhe |
|---|---|---|---|
| Hard delete LGPD (Wave 2 / B7) | 4-6 h | Logout fake | (1) Implementar `DELETE /users/me/data` no backend com cascade delete (incidents, contacts, audio em R2, settings, sessões), (2) wire na privacy_screen.dart removendo o FIXME, (3) adicionar política de retenção (ex: dados de incidents resolvidos > 1 ano podem ser anonimizados ao invés de deletados — depende do parecer jurídico) |
| Política de privacidade redigida | Tempo de advogado | Não existe | Texto legal pra app store (Apple e Google ambos exigem URL pública). Detalhar: dados coletados, finalidade, retenção, compartilhamento (PF? contatos? terceiros?), direitos LGPD |
| Termos de uso redigidos | Tempo de advogado | Não existe | Disclaimer (não substitui 190), responsabilidade limitada, condições de uso, foro |
| Apple Developer Account ativo | $99/ano | Não verificado | Pré-requisito iOS. Inclui ativar capabilities Push Notifications + Background Modes |
| Google Play Console ativo | $25 one-time | Em andamento (mencionado pelo Henrique em sessão anterior) | Pré-requisito Android |
| Disclaimer claro no app | 2-3 h | DisclaimerScreen existe mas conteúdo não auditado | "SafeCircle não substitui 190/ambulância. Em emergência médica grave, ligue 192. Em violência iminente, ligue 190." |

### 5.2 Bloqueadores Técnicos

| Item | Esforço | Status atual | Detalhe |
|---|---|---|---|
| Audit log persistente em banco (Wave 2 / B10) | 3-4 h | Em memória | Backend já tem `audit-log.entity.ts` + service, mas nenhum caller persiste de fato. Plugar em pontos críticos (login, SOS criação, secret cancel, settings change) |
| SOS delivery confirmation (Wave 2 / B8) | 3-4 h | Não existe | Mostrar pra usuária "SMS chegou em X às Y, push entregue em Z". Backend já tem `incident_deliveries` table — só falta surface no app + endpoint GET |
| Geofence sync com backend (#10) | 4-6 h | Local only | Atualmente zonas em SharedPreferences. Trocar device = perde tudo. Backend tem endpoint declarado em `api_endpoints.dart:79` (`GET /location/geofence/zones`) que ninguém implementou — precisa criar no backend + sync no mobile |
| Release signing Android (#15, #18) | 1 h | Debug key | Gerar keystore + `key.properties`, atualizar `build.gradle.kts:36-37` |
| Domínio `api.safecircle.app` configurado | Tempo de admin | Não existe | DNS + cert + Railway custom domain. Alternativa: continuar usando URL Railway nativa em prod, manter `prod` env apontando pra ela ao invés do domínio custom (decisão de produto) |
| Testes Flutter mínimos | 8-16 h | Zero (só boilerplate quebrado) | Cobrir fluxos críticos: auth, SOS criação + countdown + activate, journey start + complete, coercion PIN. Não precisa coverage 100% — 5-10 specs cobrindo cenários críticos |

### 5.3 Pesquisa de Usuárias

| Item | Esforço | Status atual | Detalhe |
|---|---|---|---|
| Consolidar pesquisa com 20+ mulheres | Tempo de admin | Sem material registrado | `FEEDBACK_USUARIAS.md` menciona "Pesquisa inicial (20+ mulheres) — _a preencher_". Apenas 1 entry de feedback contínuo registrada (botão físico). Consolidar gravações/anotações dispersas em entradas estruturadas no doc |
| Priorizar features Horizonte 3 baseado em feedback | Variável | Não começou | Pode mudar ordem do Horizonte 3. Pode também mudar Horizonte 2 se emergir bloqueador novo (ex: "10 mulheres pediram suporte a múltiplos idiomas" → vira P0) |

### 5.4 Funcionalidades incrementais

| Item | Esforço | Status atual | Detalhe |
|---|---|---|---|
| Fila offline (Wave 2 / B5) | 6-8 h | Não existe | Queue cliente-side. Backend já idempotente o suficiente pra sync deferred. App tem `OfflineQueueService.dart` declarado mas vazio/parcial — auditar |
| Lint cleanup Flutter completo (~70 issues) | 8-16 h | 72 issues | Sweep similar ao backend. Maioria é `prefer_const_constructors` (auto-fixável via IDE). Alguns deprecated_member_use que exigem migração de Switch → RadioGroup. Não bloqueador, mas higiene |
| Botão físico (3× lock / 4× volume) | 8-16 h Android, 4-8 h iOS (limitado) | Pesquisa registrada (Fase 3 original) | Da pesquisa com usuárias. Android via plugin nativo. iOS limitado (Apple reserva botão lateral) — workarounds: Back Tap, Action Button, Atalhos. **Decisão pendente (§7.5):** vale fazer no Horizonte 2 ou só no 3? Pesquisa sugere prioridade alta dentro da Fase 3, mas Horizonte 2 pode ser mais cedo se for diferencial crítico |
| Atualizar `pubspec.yaml` deps desatualizadas | 4-8 h | 42 packages com versões mais novas | `flutter pub outdated` mostra. Não urgente mas deve ser feito antes de submission stores |

### 5.5 Outputs do Horizonte 2

Ao final, deve estar entregue:

- ✅ App publicado no Google Play (closed testing inicialmente, depois open beta) e TestFlight (iOS)
- ✅ Compliance LGPD: política privacidade + termos + delete account real funcional
- ✅ Telemetria de delivery: usuária vê confirmação que SMS/push chegou
- ✅ Cobertura mínima de testes que valide fluxos críticos
- ✅ ~50-100 usuárias reais usando, gerando logs e feedback
- ✅ Pesquisa de usuárias consolidada e refletida em backlog do Horizonte 3

---

## 6. Horizonte 3 — Licitação Governo

**Objetivo:** pronto pra apresentação formal e contratação B2G via PF.

**Estimativa total:** +3-6 meses após Horizonte 2.

### 6.1 Compliance e Certificações

| Item | Esforço | Status atual |
|---|---|---|
| LGPD compliance audit completo | 2-4 semanas | Não começou |
| Certificação ISO 27001 (versão simplificada / SOC 2 Type 1) | 2-3 meses | Não começou |
| Penetration testing externo | 1-2 semanas | Não começou |
| Plano de continuidade de negócio (BCP) | Tempo de admin | Não existe |
| Plano de resposta a incidentes (IR) | Tempo de admin | Não existe |

### 6.2 Operação 24/7

| Item | Esforço | Status atual |
|---|---|---|
| Painel administrativo / dashboard de operadora | 4-8 semanas | Não existe |
| Treinamento de operadora 24/7 | Variável | Não começou |
| SLA documentado (uptime, response time, recovery time) | Tempo de admin | Não existe |
| Playbook de incidente operacional (ex: "incident escalou pra crítico, contatos não respondem, o que fazer") | Tempo de admin | Não existe |
| Monitoramento operacional avançado (alarms, dashboards Sentry/Grafana) | 1-2 semanas | Sentry configurado mas sem alarms críticos |

### 6.3 Integrações Governamentais

| Item | Esforço | Status atual |
|---|---|---|
| Integração formal com PF / PM | 2-6 meses | Não começou (vetor B2G mencionado mas sem ponto de contato técnico) |
| API pública pra órgãos públicos consumirem | 2-4 semanas | Não existe |
| Acordo de compartilhamento de dados | Jurídico | Não existe |
| Conformidade com sistemas estaduais existentes (ex: integração com 190 estaduais) | Variável | Não começou |

### 6.4 Diferenciação avançada

| Item | Esforço | Status atual |
|---|---|---|
| Voice biometrics real (TFLite + speaker verification) | 3-5 dias (se postergar pra cá) | Não existe |
| Múltiplos idiomas (i18n) | 2-3 semanas | Apenas EN/PT default — `flutter_localizations` instalado mas sem strings traduzidas |
| Smartwatch companion app (Android Wear / Apple Watch) | 4-8 semanas | Não existe |
| ML on-device pra detecção de stress vocal | 2-3 meses | Não existe (depende de pesquisa) |

---

## 7. Decisões Pendentes (Travam Direção)

Decisões que afetam ordem do roadmap mas ainda não foram tomadas. Listadas pra discussão.

### 7.1 Voice biometrics — implementar ou ajustar UI?

**Contexto:** onboarding promete "learn your unique voice pattern" e coleta 3 gravações, mas serviço de detecção nunca usa as gravações (só faz Levenshtein de texto reconhecido).

**Opções:**
- **Opção A:** implementar voice biometrics de verdade (TFLite + speaker verification). Custo: 3-5 dias. Risco técnico médio (nunca testado on-device pra Flutter). Resolve a promessa.
- **Opção B:** remover as 3 gravações do onboarding, ajustar copy pra dizer "We need your activation word" sem prometer biometria. Custo: 1 dia. Honestidade > hype.

**Recomendação:** Opção B no curto prazo (Horizonte 1), Opção A no longo prazo (Horizonte 2 ou 3). Manter UX honesta enquanto resolve features mais críticas.

### 7.2 Calculator screen — destino?

**Contexto:** modo disfarce está 100% codado (calculadora funcional + detecção de PIN), mas sem rota. Usuária não consegue acessar.

**Opções:**
- **Opção A:** virar default screen com toggle em settings ("Use Stealth Mode"). Quando ativado, app abre como calculadora; PIN entra no app real.
- **Opção B:** setting "Stealth Mode" liga/desliga, sem mudança de launcher icon (calculator vira opção em vez do dashboard quando aberto).
- **Opção C:** remover a feature inteira (descartar trabalho). Quem precisa de disfarce usa apps externos.

**Recomendação:** Opção B (mais usável que A, não descarta trabalho como C). Prioridade Horizonte 1.

### 7.3 ENVIRONMENT default — qual?

**Contexto:** app default `ENVIRONMENT=dev` em mobile. Build release sem `--dart-define` aponta pra `localhost:3000` silenciosamente.

**Opções:**
- **Opção A:** manter `dev` como default, sempre passar flag explícita em build scripts. Documentar bem.
- **Opção B:** detectar automaticamente em release builds (se `kReleaseMode == true`, default = `staging`).
- **Opção C:** forçar `staging` como default em todos os modos. Dev local precisa override explícito.

**Recomendação:** Opção B (segura por design, simples).

### 7.4 Apple Developer Account / iOS — quando registrar?

**Contexto:** iOS exige Mac pra build. Sem Apple Developer Account ativa, roadmap iOS fica bloqueado. Custo $99/ano, demora 1-2 semanas pra aprovação inicial.

**Opções:**
- **Opção A:** registrar agora (Horizonte 1), paralelizar com fixes Android. Quando Horizonte 1 acabar, iOS já está liberado pra começar.
- **Opção B:** esperar Horizonte 2 quando MVP Android estiver lançável. Foca recursos.

**Recomendação:** Opção A. Custo é baixo, paralelizar evita bloqueio futuro. Mac pode ser alugado em CI cloud (MacStadium, GitHub Actions macOS runner) sem comprar hardware.

### 7.5 Botão físico (Wave 2 ou 3?)

**Contexto:** pesquisa com usuárias gerou pedido (3× lock screen / 4× volume baixo aciona SOS). Registrado em `FEEDBACK_USUARIAS.md` como Fase 3 (Diferencial). Mas pode ser mais alta prioridade.

**Opções:**
- **Opção A:** Horizonte 2, depois de bloqueadores legais e técnicos. Diferencial pra MVP público.
- **Opção B:** Horizonte 3, apenas. Foco em compliance e operação primeiro.

**Recomendação:** Opção A se pesquisa de usuárias (§5.3) confirmar que múltiplas mulheres pediram. Opção B se for pedido isolado.

### 7.6 Pricing — quando ativar cobrança?

**Contexto:** decisão original era "não monetizar 6-12 meses". Mas quando ativar?

**Opções:**
- Sinal: ter X usuárias ativas (ex: 1000) por Y meses (ex: 3) com retenção mensurável.
- Sinal: ter caso de impacto documentado (ex: 1 usuária resgatada via SafeCircle).
- Sinal: pressão financeira (custos AWS/Twilio/Deepgram excederem comodidade).

**Recomendação:** decidir só ao chegar perto do Horizonte 3. Por agora, `Stripe` setup pode ficar em standby — backend tem nada de pagamento integrado.

---

## 8. Glossário

Termos do projeto pra quem nunca viu:

- **PF** — Polícia Federal brasileira
- **190** — Telefone de emergência da polícia (Brasil)
- **192** — Telefone de emergência médica (SAMU, Brasil)
- **LGPD** — Lei Geral de Proteção de Dados (Lei 13.709/2018, Brasil). Equivalente brasileiro do GDPR.
- **GDPR** — General Data Protection Regulation (Europa)
- **B2G** — Business to Government (vender pro governo)
- **MVP** — Minimum Viable Product (versão mínima funcional, lançável)
- **FCM** — Firebase Cloud Messaging (push notifications Google, gratuito)
- **APNs** — Apple Push Notification service (push iOS)
- **JWT** — JSON Web Token (sistema de autenticação stateless)
- **Bug 8.a** — bug crítico do risk engine (audio detectava distress mas não emitia signal pra engine). Resolvido em commit `cac6a15`. Validamos em produção que risk score escala de 70 → 100 em 6s após o fix.
- **Wave 2** — lista de débitos da auditoria original do backend (B5, B7, B8, B10) — funcionalidades novas que ainda não existem no projeto. Distinta de "Wave 1" que era cleanup imediato.
  - **B5** — Fila offline (queue cliente-side quando sem internet)
  - **B7** — Hard delete LGPD (cascade delete real)
  - **B8** — SOS delivery confirmation (mostrar entregas pra usuária)
  - **B10** — Audit log persistente em banco
- **Coercion handler** — sistema de PIN de coação. Usuária digita PIN especial → UI mostra "alerta cancelado" (pra agressor não saber) → backend silenciosamente escala incident pra CRITICAL → tracking continua. Implementado e testado.
- **Test mode** — modo demo que bypassa Twilio/Firebase no backend, mantém UI idêntica ao real. Bandeira `isTestMode: true` no incident skipa risk engine + alert dispatch waves. Usado em apresentações sem risco de SMS real ser enviado.
- **Voice biometrics** — identificar pessoa pela voz específica (não só transcrever palavra). Nome técnico: speaker verification. Não implementado.
- **R2** — Cloudflare R2, storage compatível com AWS S3 mas sem egress fee. Usado pra audio chunks.
- **Deepgram** — serviço de transcrição de áudio (speech-to-text). Backend faz POST com chunk áudio, recebe texto + confidence + words timestamps.
- **OpenAI** — usado pra análise dos sinais de socorro no texto transcrito (`AiClassifierProvider` no backend). Modelo: gpt-5-nano. Detecta "help_request", "verbal_distress", "explicit_threat", etc.
- **`@Public()`** — decorator NestJS que marca rota como pública (sem JWT). Usado em login/register/health.
- **APP_GUARD** — guard global registrado em `app.module.ts`. Protege todas as rotas exceto as marcadas `@Public`.
- **`isTestMode`** — bandeira no incident que bypassa side effects reais (Twilio, FCM, risk engine).
- **`isSecretCancel`** — bandeira no payload de cancelIncident que indica coercion. Backend escala em vez de cancelar de verdade.
- **Fase 1 / 2 / 3** — nomenclatura antiga (do `SafeCircle_Roadmap.docx` e `FEEDBACK_USUARIAS.md`). Mapeamento aproximado pro novo: Fase 1 ≈ Horizonte 1; Fase 2 ≈ Horizonte 2; Fase 3 ≈ Horizonte 3.

---

## 9. Histórico de Atualizações

- **2026-04-30 — v1.0** — Documento criado, consolidando estado pós-sweep B do backend (zero débitos ativos) e auditoria completa do mobile-app/ Flutter (22 findings, [`AUDITORIA_FLUTTER_2026-04-30.md`](AUDITORIA_FLUTTER_2026-04-30.md)). Substitui `SafeCircle_Roadmap.docx` (11/Abril, severamente desatualizado).

---

## 10. Notas finais

- **Honestidade sobre estimativas:** os números acima são conservadores e baseados em código observado, não em intenção. Erros de mais (10% do esforço) são preferíveis a erros de menos (200% do esforço).
- **Status mutável:** este documento deve ser atualizado a cada sprint/sessão. Hist em §9.
- **Quando contradição:** se algum item aqui contradiz `DEBITOS_TECNICOS.md` ou `AUDITORIA_FLUTTER_2026-04-30.md`, a fonte mais recente vence (geralmente a auditoria, que é mais granular). Reportar pra resolver.
- **Decisões em §7:** travam direção. Sem essas decisões, ordem das tarefas pode mudar drasticamente. Tomar antes de começar Horizonte 1.
