# Auditoria Flutter `mobile-app/` — 2026-04-30

Auditoria nível 2 (funcional). Read-only — zero modificações no código. Todas as letras (a)–(g) cobertas.

## Resumo Executivo

O app Flutter está **MUITO mais completo do que o roadmap docx (11/Abril/2026) sugere**. Telas, services e integração backend estão na maioria em estado de produção. Mas tem **gaps estruturais críticos** que afetam o uso real:

0. **🚨 ANDROID BUILD QUEBRADO (descoberto durante a auditoria)** — `flutter_local_notifications` requer `coreLibraryDesugaringEnabled = true` em `android/app/build.gradle.kts` que **NÃO está habilitado**. Build de debug falha: _"Dependency ':flutter_local_notifications' requires core library desugaring to be enabled for :app"_. **App não compila para Android nem em debug com a config atual.** Fix é 5 linhas (ver finding #22 e seção Build & Deploy). Prioridade ABSOLUTA — sem isso, nada funciona em Android.
1. **Push notifications remoto inexistente** — `firebase_messaging` não está no `pubspec.yaml`, `google-services.json` e `GoogleService-Info.plist` ausentes. App só recebe notificações locais. Cruza 3 features (alerta emergência → contatos, Safe Journey check-in, FCM token registration). Bloqueador real pra demo.
2. **IncidentDetailScreen é STUB** — mock hardcoded ("Marie Dupont", "Lucas Martin"), não chama backend. Usuária vê dados falsos ao clicar em qualquer incident detail.
3. **Voice biometrics prometida mas não implementada** — onboarding coleta 3 gravações com texto "learn your unique voice pattern", mas `VoiceDetectionService` ignora as gravações e usa só Levenshtein de texto reconhecido. Qualquer voz com 70% de similaridade dispara. UI mente sobre comportamento.
4. **Build de produção quebrado em release** — signing release usa debug key (TODO no `build.gradle.kts`). Não publicável na Play Store.
5. **Modo disfarce (Calculator) inerte** — código completo e funcional, sem rota no router. Usuária não consegue acessar.
6. **Default `ENVIRONMENT=dev` em mobile** — build release sem `--dart-define` explícito aponta pra `localhost:3000` silenciosamente.

Por outro lado, o app implementa funcionalidades **avançadas e sofisticadas** ausentes do roadmap docx: coercion PIN com secret cancel, always-on tracking 24/7 com Foreground Service nativo, geofencing com auto-zones a partir de learned places, test mode com bypass de Twilio backend, voice activation nativa iOS via `SilentSpeechRecognizer`, modo coerção no emergency screen com tracking continuado.

**Estado preliminar (% completude):** ~80-85% funcional, com 3 bloqueadores estruturais (#0 build, #1 push, #2 stub) que precisam ser resolvidos antes de qualquer demo. Bloqueador #0 é trivial (5 min); os outros são dias de trabalho.

**Comparação com roadmap docx:** **severamente desatualizado**. Onboarding marcado como "IN PROGRESS" está DONE com 6 steps. Voice activation marcada como "IN PROGRESS" tem código real (mas com gap de biometrics). Várias features completas não constam no roadmap.

---

## Stack e Dependências

### Versão
- App: `safecircle` v1.0.0+13
- Flutter SDK: `>=3.19.0` (instalado: 3.41.5 stable)
- Dart SDK: `>=3.3.0 <4.0.0` (instalado: 3.11.3)
- Plataformas configuradas: TODAS (`android/`, `ios/`, `web/`, `linux/`, `macos/`, `windows/`)

### Dependências (categorizadas)

| Categoria | Packages | Notas |
|---|---|---|
| Networking | `http`, `dio`, `socket_io_client` | Socket.io alinha com NestJS WebSocket Gateway |
| State Mgmt | `provider` | Não bloc/riverpod |
| Routing | `go_router` v14 | Moderno |
| Storage | `flutter_secure_storage`, `shared_preferences`, `path_provider` | Secure storage pra JWT |
| Location | `geolocator`, `flutter_map`, `latlong2` | flutter_map (não Google Maps SDK) |
| **Audio** | `record`, `speech_to_text`, `audio_session` | Voice activation possível |
| Auth | `local_auth`, `permission_handler` | Biometria (não vi uso ativo) |
| **Notifications** | `flutter_local_notifications` | **🚨 SEM `firebase_messaging`** |
| Outros | `url_launcher`, `intl_phone_field`, `uuid`, `intl`, `crypto`, `sentry_flutter` | Phone international ✓ |
| **AUSENTES** | `firebase_core`, `firebase_messaging`, `tflite_flutter` | Push remoto + ML local não existem |

### Estrutura de pastas em `lib/` (65 arquivos)

```
lib/
├── main.dart (414 linhas)
├── core/
│   ├── api/         api_client.dart, api_endpoints.dart
│   ├── auth/        auth_service.dart, auth_state.dart
│   ├── config/      env.dart, app_config.dart, router.dart
│   ├── models/      8 modelos (incident, journey, contact, etc.)
│   ├── services/    18 services
│   ├── storage/     secure_storage.dart
│   ├── theme/       app_theme, theme_notifier
│   ├── utils/       coercion_handler
│   └── widgets/     loading_overlay, safe_button
└── features/
    ├── onboarding/  onboarding_screen, permissions_step, voice_activation_step
    ├── auth/        login, register
    ├── dashboard/
    ├── contacts/    list + add
    ├── journey/     list + active
    ├── emergency/   screen + countdown_widget + active_widget
    ├── incidents/   history + detail
    ├── settings/    main + 6 subscreens
    ├── disguise/    calculator_screen
    ├── test_mode/
    ├── help/        help + disclaimer
    ├── map/         live_map_screen
    └── diagnostics/ system_readiness_screen
```

---

## Mapa de Telas

| Path | Tela | Status real | Conecta backend? |
|---|---|---|---|
| `/splash` | SplashScreen com safety timer 10s | ✅ Funcional | Indireto via auth |
| `/auth/login` | LoginScreen | ✅ Funcional | POST /auth/login |
| `/auth/register` | RegisterScreen | ✅ Funcional | POST /auth/register |
| `/onboarding` | OnboardingScreen 6 steps | ✅ Completo (~docx diz IN PROGRESS, está DONE) | Múltiplos |
| `/home` | DashboardScreen | ✅ Funcional | POST /incidents (long-press) |
| `/contacts` | ContactsScreen | ✅ Funcional | GET/DELETE /contacts |
| `/contacts/add` `/contacts/edit/:id` | AddContactScreen | ✅ Funcional | POST/PUT /contacts |
| `/settings` (+6 sub) | Settings hub | ✅ Funcional | Múltiplos |
| `/settings/coercion-pin` | CoercionPinScreen | ✅ **Sofisticado** | PUT /settings/emergency/coercion-pin |
| `/settings/voice` | VoiceSettingsScreen | ✅ Funcional | Local |
| `/settings/geofence` | GeofenceSettingsScreen | ⚠️ Local-only (não sincroniza backend) | Não |
| `/emergency` | EmergencyScreen 4-state (countdown/active/coercion/ended) | ✅ **Excelente** | POST /incidents/:id/* |
| `/incidents` | IncidentHistoryScreen | ✅ Funcional | GET /incidents |
| **`/incidents/:id`** | **IncidentDetailScreen** | **⚠️ STUB com mock hardcoded** ("Marie Dupont", "Lucas Martin") | **NÃO chama backend** |
| `/test-mode` | TestModeScreen | ✅ Real, usa `isTestMode: true` | POST /incidents (test) |
| `/journey` `/journey/active` | Journey + Active | ⚠️ Funcional MAS check-in push quebrado | POST /journey/* |
| `/map` | LiveMapScreen | (não auditado em profundidade) | Provavelmente WS + GET |
| `/diagnostics` | SystemReadinessScreen | (não auditado em profundidade) | — |
| `/help` `/disclaimer` | Help + Disclaimer | ✅ Funcional | Local |
| **(sem rota)** | **CalculatorScreen** | **❌ Código completo SEM ROTA** | — |

**23 rotas configuradas, 1 tela inerte (CalculatorScreen).**

---

## Integração Backend

### URL backend — `app_config.dart`

| Env | API URL | WS URL | Status |
|---|---|---|---|
| `dev` | `http://localhost:3000/api/v1` ou `http://10.0.2.2:3000/api/v1` (Android emu) | `ws://...` | Local |
| `staging` | `https://perfect-expression-production-0290.up.railway.app/api/v1` | `wss://...railway.app` | ✅ Backend que validamos |
| `prod` | `https://api.safecircle.app/api/v1` | `wss://api.safecircle.app` | ❌ **Domínio não existe** |

**Como o app sabe o environment:**
- `String.fromEnvironment('ENVIRONMENT', defaultValue: 'dev')` em `main.dart:52`
- Mobile: depende de `--dart-define=ENVIRONMENT=staging` no build
- Web: auto-detect baseado em `Uri.base.host` (localhost/railway.app/outros)

### Endpoints declarados (api_endpoints.dart)

~60 endpoints. Match com backend resumido:

| Categoria | Match | Notas |
|---|---|---|
| Auth (login, register, refresh, logout) | ✅ | |
| Incidents (CRUD + activate/resolve/cancel/signal/events) | ✅ | |
| Audio upload/list/download/transcripts | ✅ | |
| Location (per-incident) | ✅ | |
| Timeline | ✅ | |
| Notifications (respond/deliveries/responses) | ✅ | |
| Contacts CRUD | ✅ | |
| Settings (`/settings/emergency`, `/coercion-pin`) | ✅ | |
| Users (`/users/me`) | ✅ | |
| **`/users/me/devices` (registerDevice)** | **❌ Backend não tem** | Constante declarada mas **nunca chamada** no código — dead constant |
| Journey (7 sub-rotas) | ✅ | |
| Location tracking (track/batch/latest/places) | ✅ | |
| Geofence `/location/geofence/events` | ✅ | |
| **Geofence `/location/geofence/zones`** | **❌ Backend não tem** | Constante declarada mas **nunca chamada** — dead constant |
| `/health` | ✅ | |

### JWT storage e refresh

**Storage:** `flutter_secure_storage` com:
- Android: `encryptedSharedPreferences: true` (Keystore-backed) ✅
- iOS: `KeychainAccessibility.first_unlock_this_device` ✅

**Refresh implementation** (api_client.dart) — **industry-grade**:
- `_AuthInterceptor.onError` detecta 401 → refresh → re-tenta request original
- `_refreshCompleter` previne refreshes concorrentes (várias 401 simultâneas → só 1 refresh)
- Backend retorna `{tokens:{access,refresh}}` ou flat — handler trata ambos
- **Refresh proativo** via Timer em AuthService (cada 13min: TTL 15min - buffer 2min)
- Auto-login com 20s timeout safety

**Comportamento em 401:** **(a) refresh automático + re-tenta o request.** Industry-grade.

### Error handling

| Comportamento | Implementação |
|---|---|
| Try/catch | ✅ Em todos os services |
| Loading states | ✅ Specific por screen |
| Retry em network error | ✅ Max 2 retries, backoff exponencial 500ms→1000ms |
| Backend offline timeout | ✅ connect 15s, receive 15s, send 30s, upload 60s |
| Recovery "stale incident" | ✅ Dialog interativo (cancel old / go to / dismiss) |
| Splash safety timeout | ✅ 10s no SplashScreen + 20s no tryAutoLogin |

### WebSocket — match perfeito com backend

`websocket_service.dart` (200 linhas):
- `socket_io_client` (correto — backend usa NestJS Socket.IO Gateway)
- Conecta em `${wsUrl}/incidents` namespace
- Auth dual via JWT: `setAuth({token}) + setQuery({token})` (header + query, defensivo)
- **Auto-reconnect** 10 tentativas, delay 2s→30s
- **6 eventos do gateway escutados:** `incident:update`, `location:update`, `risk:update`, `alert:update`, `contact:response`, `timeline:event` — match exato com `incident.gateway.ts:115-159`
- Streams broadcast pra múltiplos consumers
- Re-join automático após reconnect

### Hardcoded credentials

**ZERO encontrados.** Único match: `mapboxToken = ''` (default vazio em const, não credential real). App is clean.

---

## Funcionalidades Nativas — Estado Real

### Permissões

Android (`AndroidManifest.xml`) — 13 permissões corretas, incluindo `FOREGROUND_SERVICE_LOCATION` e `FOREGROUND_SERVICE_MICROPHONE` (Android 14+ compliant). Service declarado com `foregroundServiceType="location|microphone"`. BootReceiver pra restart pós-reboot.

iOS (`Info.plist`):
- `UIBackgroundModes`: `location, audio, fetch, processing` ✅
- `BGTaskSchedulerPermittedIdentifiers` ✅
- Todas as `NSXxxUsageDescription` mensagens honestas ✅

**Comportamento se usuária NEGA:**
- Microfone: degradação graciosa (audio_service retorna sem gravar)
- Localização foreground: incident criado **sem coordenada** (não bloqueia)
- Localização background: log + skip (app funciona normal)
- Notifications: SnackBar + `openAppSettings()` deeplink

### Audio recording (`audio_service.dart`)

| Param | Valor |
|---|---|
| Encoder | AAC LC |
| Sample rate | 44100 Hz |
| Bitrate | 128 kbps |
| Channels | 1 (mono) |
| Container | `.m4a` |
| Chunk duration | 30 segundos |
| Storage | `getTemporaryDirectory()` |
| Upload | multipart/form-data, contentType `audio/mp4` |
| Endpoint | `POST /incidents/:id/audio?duration=30` |
| Cleanup | File deletado após upload sucesso. **Mantido se falhar mas SEM retry implementado** |

**Consent gating:** `_consentLevel.canRecord` validado. Se `none` → não grava.

**Coercion mode:** `stopRecording()` em `_cleanupActiveIncident` (cancel/resolve normal). Em secret cancel **NÃO PARA** ✓.

**Backend match:** Confirmado em sessões anteriores — multipart aceito, chunkIndex server-side.

### Location tracking (`location_tracker_service.dart` + `background_service.dart`)

- **Foreground:** timer Dart 5min + initial capture
- **Background:** native push via MethodChannel `com.safecircle.app/background` → método `onLocationUpdate`
- iOS: `significant location change` para killed-app recovery (~500m) + UIBackgroundModes contínuo
- Android: ForegroundService Kotlin com WakeLock partial + START_STICKY + onTaskRemoved → reschedule
- BootReceiver restart pós-reboot
- Sync: `POST /location/track` por snapshot + batch (até 100 entries)
- Local SharedPreferences max 2000 entries, prune automático
- Battery optimization exemption request via MethodChannel

### Voice activation (`voice_detection_service.dart` — 469 linhas)

**Implementação dual:**
- iOS: native `SilentSpeechRecognizer.swift` via MethodChannel `com.safecircle.app/voice` (AVAudioEngine + SFSpeechRecognizer) — **zero "ding" sound**
- Android: `speech_to_text` package + AudioSession silent mode

**Match com palavra ativação:**
- Levenshtein distance fuzzy matching, threshold **0.70 confidence**
- Continuous listening 60s sessions + auto-restart 2s delay
- Auto-start se enabled

**🔴 GAP CRÍTICO — Voice biometrics PROMETIDA, NÃO IMPLEMENTADA:**

`voice_activation_step.dart` no onboarding coleta 3 gravações com texto:
> "We need 3 recordings to **learn your unique voice pattern**"
> "SafeCircle will learn to recognize your **unique voice pattern**"

Mas:
- 3 gravações são salvas em `ApplicationDocumentsDirectory` + paths em SharedPreferences (`safecircle_voice_samples`)
- `voice_detection_service.dart` **NUNCA carrega/usa essas gravações**
- Matching é puramente baseado em texto reconhecido (Levenshtein)
- Qualquer voz que diga a palavra com 70%+ similaridade dispara

**Threshold 70% análise empírica:**

| Activation | Recognized | Sim. | Match? |
|---|---|---|---|
| `ajuda` (5) | `ajudar` (6) | 0.83 | ✅ |
| `socorro` (7) | `socorrida` (9) | 0.67 | ❌ |
| `help me` (7) | `Hellome` (7) | 0.71 | ✅ ⚠️ falso positivo plausível |

**Sobrevivência a app kill:** Native Android (BootReceiver restart ForegroundService) sobrevive reboot, mas **VoiceDetectionService Dart não inicializa até user abrir app**. Voice activation PARA se attacker forçar kill via Settings. Limitação estrutural Flutter.

### Push notifications (`notification_service.dart`)

`flutter_local_notifications` only:
- 3 channels Android: `emergency_channel` (max+full screen+alarm), `general_channel`, `tracking_channel` (low, ongoing)
- iOS: critical interruption level
- `setFcmToken()` declarado mas **NUNCA chamado** — dead code
- `getFcmToken()` retorna null sempre

**🔴 SEM PUSH REMOTO** — finding crítico #1 cruza com #11 e #16.

### SOS button (long-press)

`dashboard_screen.dart`:
- `GestureDetector(onLongPress: _triggerEmergency)`
- HapticFeedback.heavyImpact ao iniciar
- Round button vermelho + "HOLD" label
- Cria incident no backend, navega `/emergency`
- Recovery dialog se backend tem stale incident
- Test mode toggle (vai pra `/test-mode`)

**Countdown:**
- Backend retorna `countdownEndsAt`. App calcula `remaining`. Default fallback 5s
- Test mode passa `countdownSeconds: 10` explícito
- Manual SOS sem param → backend usa default próprio (5s observado)

**Cancel options:**
- (a) PIN normal → `cancelIncident` + cleanup
- (b) PIN coerção → `secretCancelIncident` + UI cancelled fake (tracking continua)
- (c) Triple secret tap (80×80 zona invisível top-right, 3 taps em 2s) → `widget.onCancel()`

### Safe Journey (`journey_service.dart` — 243 linhas)

7 endpoints completamente implementados (start/getActive/checkin/complete/respondCheckin/cancel/sendLocation). Auto-tracking via `LocationService.locationStream` listener. Backend match perfeito.

**🔴 Check-in push quebrado em prod:** Backend dispara FCM quando timer expira, app não tem `firebase_messaging` pra receber. Check-in flow só funciona se app estiver aberto e em foreground.

### Geofence (`geofence_service.dart` — 453 linhas)

- 3 tipos: safe (alert on exit), watch (alert on entry), custom
- Hysteresis 20m
- Check interval 30s
- Haversine distance
- Auto-criadas a partir de `LearnedPlacesService` (3+ visits OU `isConfirmedSafe`)

**🟡 Zonas LOCAL only** — armazenadas em SharedPreferences (`safecircle_geofences`). Backend declara `GET /location/geofence/zones` mas app nunca chama. Trocar dispositivo = perde zonas.

Geofence event reportado ao backend só **indiretamente** via `incidentService.sendRiskSignal('geofence_exit')` se houver incident ativo, ou via novo incident triggered.

### Coercion handler (`coercion_handler.dart`)

**Sofisticado, SAFETY-CRITICAL:**
- SHA256 hash local + bcrypt backend (separados)
- Coercion PIN → `secretCancelIncident()` envia `isSecretCancel: true` ao backend MAS NÃO PARA tracking local
- Normal PIN → `cancelIncident()` para tudo
- UI mostra "cancelled" pros 2 casos (impossível pro agressor distinguir)
- `EmergencyScreen._onCoercionCancel()` muda UI pra "modo coerção" mantendo tracking real

### Calculator (modo disfarce)

**Código completo e funcional** mas **SEM ROTA** no router. Detecta PIN dentro do digit sequence (4-8 dígitos antes do `=`) e navega `/home` se match. Calculator real funcional além disso. **Inerte na prática** — usuária não consegue acessar.

---

## Build & Deploy

### Android

`build.gradle.kts` (`android/app/`):
- applicationId: `com.safecircle.safecircle`
- compileSdk/minSdk/targetSdk: do flutter (versionCode/versionName idem)
- Java 17, Kotlin JVM 17
- **Sem Google Services plugin aplicado** (nem no project-level nem app-level)

#### 🚨 BLOQUEADOR ABSOLUTO — Build Android falha por falta de core library desugaring

**App não compila para Android nem em debug com a config atual.** Descoberto durante a auditoria via `flutter build apk --debug --dart-define=ENVIRONMENT=staging` (build correu por 13min 31s antes de falhar):

```
FAILURE: Build failed with an exception.
* What went wrong:
Execution failed for task ':app:checkDebugAarMetadata'.
> A failure occurred while executing CheckAarMetadataWorkAction
   > An issue was found when checking AAR metadata:
       1.  Dependency ':flutter_local_notifications' requires core
           library desugaring to be enabled for :app.
```

**Causa:** `flutter_local_notifications` v17+ usa APIs de Java 8+ (`java.time`, `java.util.Optional`) que precisam de "core library desugaring" pra rodar em Android < 26.

**Fix mapeado (5 minutos, ~5 linhas em `android/app/build.gradle.kts`):**

```kts
android {
  compileOptions {
    isCoreLibraryDesugaringEnabled = true   // ← adicionar
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
  }
}

dependencies {                              // ← adicionar bloco inteiro
  coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

**Severidade:** 🔴 CRÍTICO — bloqueador ABSOLUTO. Sem isso:
- App não compila nem em debug
- Impossível testar no celular
- Impossível gerar APK pra QA, pra interna ou pra produção
- Reforça findings #15 (release signing) e #16 (google-services.json) — ordem de fix: este finding (#22) deve vir ANTES dos outros 2

#### Outros achados Android

- **🔴 Release signing usa debug key:**
  ```kts
  release {
    // TODO: Add your own signing config for the release build.
    signingConfig = signingConfigs.getByName("debug")
  }
  ```
  Não publicável na Play Store.

**Configs ausentes:**
- ❌ `android/app/google-services.json` (Firebase Android NÃO configurado)
- ❌ `android/key.properties` (signing release não configurado)

**Native Kotlin (3 arquivos completos e bem implementados):**
- `MainActivity.kt`: MethodChannel `com.safecircle.app/background` com 5 métodos (start/stop service, isRunning, requestBatteryExemption, isBatteryExempt)
- `SafeCircleForegroundService.kt`: foreground service com WakeLock partial, START_STICKY, persistent notification (SECRET visibility), onTaskRemoved → reschedule
- `BootReceiver.kt`: ACTION_BOOT_COMPLETED + MY_PACKAGE_REPLACED → restart se always-on flag

### iOS

`ios/Runner/`:
- AppDelegate.swift, SceneDelegate.swift
- **`SilentSpeechRecognizer.swift`** ← native voice activation pra zero-ding iOS
- Info.plist (auditado — TUDO presente)
- `ExportOptions.plist` presente

**Configs ausentes:**
- ❌ `ios/Runner/GoogleService-Info.plist` (Firebase iOS NÃO configurado)
- ❌ Apple Developer team ID em project.pbxproj não verificado em profundidade (mas Bundle ID = `$(PRODUCT_BUNDLE_IDENTIFIER)` — placeholder, vem da config)

### Build de teste

Tentativa: `flutter build apk --debug --dart-define=ENVIRONMENT=staging`

**FALHOU em 13min 31s** com erro genuíno de configuração do projeto (NÃO ambiente):

```
FAILURE: Build failed with an exception.
* What went wrong:
Execution failed for task ':app:checkDebugAarMetadata'.
> Dependency ':flutter_local_notifications' requires core library desugaring
  to be enabled for :app.

BUILD FAILED in 13m 31s
```

**Análise:**
- Android SDK 34 foi baixado durante o build (não estava instalado) — esperado
- Aviso "Developer Mode required for symlink support" apareceu durante `pub get` mas é **warning, não fatal** — `pub get` completou com sucesso
- A real falha foi a falta de `coreLibraryDesugaringEnabled` (vide finding #22 acima)

**Severidade:** Bug REAL do projeto, não ambiental. Mesma falha vai ocorrer em qualquer máquina (Linux/Mac/Windows) até o fix das 5 linhas ser aplicado.

---

## Qualidade de Código

### `flutter analyze` — 72 issues

| Severidade | Count |
|---|---|
| **Error** | **1** |
| Warning | 9 |
| Info | 62 |
| **Total** | **72** |

**Top 10 categorias:**

| # | Rule | Count |
|---|---|---|
| 1 | `prefer_const_constructors` (perf hint) | 36 |
| 2 | `deprecated_member_use` (Switch onChanged etc) | 13 |
| 3 | `curly_braces_in_flow_control_structures` | 7 |
| 4 | `unused_import` | 5 |
| 5 | `use_build_context_synchronously` | 5 |
| 6 | `prefer_const_declarations` | 1 |
| 7 | `unused_element` | 1 |
| 8 | `unused_field` | 1 |
| 9 | `unused_element_parameter` | 1 |
| 10 | `unused_local_variable` | 1 |

**1 error específico:** `test/widget_test.dart:16` — `MyApp` not a class. Test boilerplate quebrado, nunca foi atualizado pra `SafeCircleApp`.

**Sweep similar ao backend possível:** seria ~1-2h de cleanup mecânico. Maioria é `prefer_const_constructors` (auto-fixável via IDE).

### TODOs / FIXMEs encontrados

| File:Line | Tipo | Conteúdo |
|---|---|---|
| `privacy_screen.dart:327` | **FIXME** | "This only logs the user out. Full data deletion requires a DELETE /users/me/data backend endpoint that cascade-deletes all related data. That endpoint exists in the plan but may not be implemented yet." |
| `incident_detail_screen.dart:13` | TODO | "Load incident from provider/service using incidentId" |
| `incident_detail_screen.dart:195` | TODO | "Delete incident via service" |

**🟡 IncidentDetailScreen é STUB com mock hardcoded** — mostra dados FAKE (`Marie Dupont`, `Lucas Martin`) ao clicar em qualquer incident. **Não chama backend.**

**🟡 Delete account incompleto** — privacy_screen.dart "deleta" só fazendo logout. Backend pode ou não ter `DELETE /users/me/data` (não validamos).

### Tests

`test/widget_test.dart` apenas — boilerplate Flutter default quebrado (refere-se a `MyApp` que não existe). **Sem testes reais escritos.**

---

## Roadmap Docx vs Realidade

Cruzando todos os achados (a)–(f) contra `SafeCircle_Roadmap.docx` (11/Abril/2026):

### Items DONE no docx

| Item | Realidade | Notas |
|---|---|---|
| Backend API | ✅ Realmente done | Validado em sessões anteriores |
| Frontend Web | (não auditado nesta sessão) | Fora de escopo |
| Autenticação | ✅ Realmente done | login/register/JWT/refresh industry-grade |
| Dashboard SOS | ✅ Realmente done | Long-press, countdown, active state, recovery dialog |
| Contatos confiança | ✅ Realmente done | CRUD + service + UI completos |
| Safe Journey | ⚠️ **Done parcial** | Código completo MAS check-in push QUEBRADO sem firebase_messaging |
| Alerta emergência | ⚠️ **Done parcial** | Long-press funciona MAS contatos NÃO recebem push remoto se app fechado |
| Dark Mode | ✅ Realmente done | ThemeNotifier + MaterialApp.themeMode integrado |
| Telefone internacional | ✅ Realmente done | intl_phone_field, default BR |

### Items IN PROGRESS no docx

| Item | Realidade | Notas |
|---|---|---|
| Onboarding 6 steps | ❌ **JÁ DONE** | 6 steps completos. Roadmap desatualizado. |
| Gravação palavra ativação | ⚠️ **Parcial — voice biometrics não existe** | Código real e funcional pra detecção. Mas voice biometrics PROMETIDA na UI ("learn your unique voice pattern") NÃO implementada. Gravações coletadas e descartadas. |

### Items PLANNED no docx

| Item | Realidade | Notas |
|---|---|---|
| Build Mobile iOS/Android | ⚠️ **Tem stub avançado** | Native code completo (Kotlin/Swift), permissions corretas. MAS sem signing release, sem Firebase, sem Apple Dev Team ID, sem build pipeline. **NÃO pronto pra publicar nas stores.** |

### Features que EXISTEM no app mas NÃO ESTÃO no docx

| Feature | Estado |
|---|---|
| Modo disfarce (Calculator) | ❌ Código completo, **SEM ROTA** (inerte) |
| Coercion PIN + Secret Cancel | ✅ Implementação SAFETY-CRITICAL sofisticada |
| Geofencing com auto-zones | ⚠️ Local-only (não sync backend) |
| Always-on tracking 24/7 | ✅ Native FG service (Android) + UIBackgroundModes (iOS) |
| Voice activation iOS native (silent) | ✅ `SilentSpeechRecognizer.swift` |
| Test mode com isTestMode flag | ✅ Bypassa Twilio backend |
| Modo coerção no emergency screen | ✅ Mantém tracking durante UI fake "cancelled" |
| Live map | (não auditado em profundidade) |
| System Diagnostics | (não auditado em profundidade) |
| Help / Disclaimer | ✅ Existem |
| Learned places service | (não auditado em profundidade) |
| SMS fallback service | (não auditado em profundidade) |
| Offline queue service | (não auditado em profundidade) |
| Sentry crash reporting | ✅ Configurado via --dart-define |

**Conclusão:** roadmap docx está **severamente desatualizado**. App tem ~12 features avançadas não documentadas, com 2 IN PROGRESS já DONE, e 1 marcado DONE (alerta emergência) que tem gap crítico (push remoto).

---

## Bugs Encontrados (sem fix)

| # | Bug | Local | Severidade |
|---|---|---|---|
| 1 | **Sem `firebase_messaging`** — push remoto quebrado entre backend e app | `pubspec.yaml` | 🔴 Crítico |
| 2 | **Sem voice biometrics** — onboarding promete "learn your unique voice pattern", `VoiceDetectionService` ignora gravações coletadas | `voice_detection_service.dart` vs `voice_activation_step.dart` | 🔴 Crítico |
| 3 | **Coercion mode sync em rede ruim** — `_isCoercionMode = true` setado APÓS `await api.post(cancel)`. Se rede falha, UI mostra cancelled mas IncidentService flag fica errado | `incident_service.dart:159-178` | 🟡 Médio |
| 4 | **Default `ENVIRONMENT=dev` em mobile** — build release sem `--dart-define` aponta pra `localhost:3000` silenciosamente | `main.dart:52` | 🔴 Crítico |
| 5 | **`prod` env aponta pra `api.safecircle.app` que não existe** — domínio não configurado em DNS | `app_config.dart:60` | 🟡 Médio |
| 6 | **`registerDevice` + `geofenceZones` declarados mas backend não tem** — dead constants | `api_endpoints.dart:57, 79` | 🟢 Baixo |
| 7 | **`fcm_token` storage existe mas nunca é populado** — sem firebase_messaging, intent quebrado | `secure_storage.dart:8` + `notification_service.dart:51` | 🟡 Médio (cruza #1) |
| 8 | **CalculatorScreen sem rota** — disfarce inerte | `router.dart` | 🔴 Crítico |
| 9 | **Safe Journey check-in push quebrado** sem firebase_messaging | `journey_service.dart` (cruza #1) | 🔴 Crítico |
| 10 | **Geofence zones LOCAL only** — não sync backend, perde no troca de dispositivo | `geofence_service.dart` | 🟡 Médio |
| 11 | **Voice activation não sobrevive app kill explícito** — Dart side só roda com app aberto | Estrutural Flutter | 🟢 Info |
| 12 | **Audio chunks sem retry de upload** — falhou = arquivo fica local | `audio_service.dart:147` | 🟡 Médio |
| 13 | **IncidentDetailScreen é STUB** — mock hardcoded ("Marie Dupont", "Lucas Martin"), não chama backend | `incident_detail_screen.dart:13` | 🟡 Médio |
| 14 | **Delete account incompleto** — só faz logout, não deleta dados | `privacy_screen.dart:327` | 🟡 Médio |
| 15 | **Release signing usa debug key** — não publicável Play Store | `android/app/build.gradle.kts:36-37` | 🔴 Crítico (bloqueador deploy) |
| 16 | **Sem `google-services.json`** | `android/app/` | 🔴 Crítico (cruza #1) |
| 17 | **Sem `GoogleService-Info.plist`** | `ios/Runner/` | 🔴 Crítico (cruza #1) |
| 18 | **Sem `key.properties`** | `android/` | 🔴 Crítico (cruza #15) |
| 19 | **flutter analyze: 1 error + 9 warnings + 62 infos** — boilerplate quebrado em widget_test, deprecated members, perf hints | `lib/` + `test/` | 🟡 Médio |
| 20 | **SOS triple-secret-tap sem PIN** — security through obscurity (trade-off aceitável) | `countdown_widget.dart:253-262` | 🟢 Info |
| **22** | **🚨 Build Android quebrado por falta de core library desugaring** — `flutter_local_notifications` exige `coreLibraryDesugaringEnabled = true` em `compileOptions` + dependência `desugar_jdk_libs`. App não compila nem em debug. Fix é 5 linhas. Descoberto via `flutter build apk --debug` na auditoria (build correu 13m31s antes de falhar) | `android/app/build.gradle.kts` | 🔴 **CRÍTICO ABSOLUTO** (P0) |

> **Nota:** finding #21 foi reservado pra "native config completa Android/iOS" como achado positivo (vide letra (d)). Não há "bug" #21 — é um achado neutro/positivo registrado durante a auditoria.

---

## Gaps Identificados

### Bloqueadores pra demo de produção (DEMO-BLOCKING)

1. **Push notifications remoto inexistente** — afeta alerta emergência → contatos, Safe Journey check-in, FCM token registration. Backend envia FCM, app não tem como receber. **Falsos positivos sistêmicos esperados** (mulher não responde check-in que nunca chegou → escalação dispara alertas falsos).
2. **Voice biometrics não implementada** — UI mente sobre comportamento. Falsos positivos por TV/crianças/agressor são reais.
3. **Modo disfarce inerte** — feature de segurança crítica não acessível.
4. **Build release não publicável** — signing com debug key.
5. **Configuração Firebase ausente** — sem `google-services.json` / `GoogleService-Info.plist`.

### Bloqueadores pra publicação store (DEPLOYMENT-BLOCKING)

6. Apple Developer team ID não configurado/verificado em profundidade
7. Release keystore não criado
8. iOS signing & capabilities (Push Notifications, Background Modes ativados na Apple Developer Account) não validados

### Gaps funcionais não-críticos

9. IncidentDetailScreen mock hardcoded (não exibe dados reais)
10. Delete account não cascadeia dados
11. Geofence zones LOCAL only (sem sync backend / cross-device)
12. Audio chunks sem retry de upload
13. Voice activation não sobrevive app kill (limitação estrutural)

### Gaps em testes

14. Sem testes reais (só widget_test.dart boilerplate quebrado)
15. Sem CI/CD pipeline aparente

---

## Riscos & Bloqueadores

### Pré-publicação imediata

- **Apple Developer Account ativa?** (necessário pra TestFlight/App Store)
  - Push Notifications capability ativada?
  - Background Modes (Location, Audio, Background Fetch, Background Processing) ativados?
  - APNs Auth Key gerada?
- **Google Play Console ativa?** (necessário pra Play Store interna/produção)
- **Firebase project criado** com config files baixados?
- **DNS `api.safecircle.app`** configurado pra produção?

### Build infrastructure

- Windows Developer Mode requirement pra builds locais (pode ser contornado via VM/Mac/CI)
- **Sem CI/CD pipeline** aparente (GitHub Actions, etc.)
- Builds de release manuais com `--dart-define` necessário

### Compliance

- iOS critical interruption level (notificações) requer aprovação Apple — não trivial
- Android `FOREGROUND_SERVICE_LOCATION` Play Store policy compliance precisa ser validado (Google scrutinia)
- LGPD/GDPR — Privacy policy + Terms já têm telas, mas conteúdo não foi auditado

---

## Próximos Passos Recomendados

Lista priorizada **pra discussão** — input pro roadmap consolidado, sem comprometer ainda:

### P0 ABSOLUTO — UNBLOCK BUILD (5 minutos, fazer ANTES de tudo)

0. **🚨 Habilitar core library desugaring** em `android/app/build.gradle.kts`. **5 linhas, ~5 minutos.** Sem isso, app não compila nem em debug pra Android. Bloqueia QUALQUER tentativa de testar no celular ou de demo. **Resolve finding #22.**

   ```kts
   compileOptions {
     isCoreLibraryDesugaringEnabled = true
     sourceCompatibility = JavaVersion.VERSION_17
     targetCompatibility = JavaVersion.VERSION_17
   }
   dependencies {
     coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
   }
   ```

### P0 — DEMO BLOCKERS (depois do P0 absoluto)

1. **Implementar IncidentDetailScreen real** — atualmente mostra mock hardcoded. ~30 min se IncidentService já tem `getIncident(id)` e `getTimeline(id)` (tem). **Resolve findings #13, TODO em incident_detail_screen.dart:13.**
2. **Adicionar `firebase_messaging` ao `pubspec.yaml`** + criar projeto Firebase + adicionar `google-services.json`/`GoogleService-Info.plist` + wire FCM token registration → backend `/users/me/devices` (que precisa ser criado também). **Resolve findings #1, #11, #16, #17.**
3. **Decidir destino do Calculator (modo disfarce):** roteá-lo OU remover. Se manter, definir como user acessa (settings toggle? launcher disguise?). **Resolve finding #8.**
4. **Decidir voice biometrics:** (a) implementar usando MFCC/embeddings (escopo grande, ~3-5 dias) OU (b) atualizar UI pra remover promessa de "voice pattern". Honestidade > hype. **Resolve finding #2.**

### P1 — RELEASE BLOCKERS (próximo sprint)

4. Configurar release signing Android (`key.properties` + keystore). Bloqueador Play Store.
5. Configurar Apple Developer Account + TestFlight pipeline.
6. Configurar DNS `api.safecircle.app` OU mudar default mobile pra `staging`.
7. Setup CI/CD (GitHub Actions): `flutter analyze` + build Android + sign + publish to TestFlight automated.

### P2 — QUALITY (sweep dedicado)

8. Sweep `flutter analyze`: 72 → 0 issues. Esforço estimado 1-2h (similar ao backend).
9. Implementar IncidentDetailScreen real (substituir mock). Esforço ~30min.
10. Implementar `DELETE /users/me/data` no backend + cascade delete. Esforço ~1-2h.
11. Adicionar retry de upload em audio chunks. Esforço ~30min.

### P3 — PRODUCT POLISH

12. Sync geofence zones com backend pra cross-device. Esforço médio.
13. Adicionar testes (integration + widget tests reais). Esforço alto.
14. Atualizar `pubspec.yaml` deps desatualizadas (42 packages com versões mais novas — `flutter pub outdated` mostra).

---

## Top 6 bloqueadores pra demo (ordem recomendada de fix)

| Ordem | Bloqueador | Esforço | Notas |
|---|---|---|---|
| **1** | **🚨 Build Android desugaring** (#22) | **5 minutos** | P0 absoluto — sem isso, NADA funciona em Android. Faz primeiro. |
| 2 | Push remoto FCM (#1, #11, #16, #17) | 2-3 dias | Firebase setup + firebase_messaging + backend `/users/me/devices` |
| 3 | IncidentDetailScreen STUB (#13) | ~30 min | IncidentService já tem getIncident + getTimeline |
| 4 | Voice biometrics promessa (#2) | 1 dia (UI) ou 3-5 dias (impl) | Decisão de produto: prometer menos OU implementar |
| 5 | Calculator sem rota (#8) | 30min-2h | Decisão de produto: rotear ou remover |
| 6 | ENVIRONMENT default + release signing (#4, #15, #18) | 1h | Mudar default pra `staging` + gerar keystore + key.properties |

---

## Observação final

App está em **estado avançado de implementação** mas tem **gaps estruturais críticos** que precisam ser endereçados antes de demo. **3 maiores riscos:**

1. **🚨 Build Android quebrado** — descoberto durante a auditoria. Sem fix do desugaring (5 linhas), app não compila nem em debug. Trivial mas absolutamente bloqueador. **Faz isso primeiro de tudo.**
2. **Push remoto inexistente** — quebra fluxo central (notificar contatos quando app fechado, check-in Safe Journey, FCM token registration).
3. **Voice biometrics prometida mas não implementada** — problema de **trust**. UI mente sobre comportamento.

Pós-fix #1 (desugaring), os outros 2 podem ser endereçados em ~1 sprint dedicado:
- Push: ~2-3 dias (Firebase setup + integração + backend `/users/me/devices`)
- Voice: ~1 dia se for atualizar UI honestamente, ~3-5 dias se for implementar biometrics

Roadmap docx precisa ser **completamente refeito** — não reflete realidade do código.
