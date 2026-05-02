import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/secure_storage.dart';
import 'voiceprint_service.dart';

/// Continuous voice detection service — SILENT operation.
///
/// ## Platform Strategy
///
/// **iOS**: Uses native `SilentSpeechRecognizer` (AVAudioEngine + SFSpeechRecognizer)
///   via MethodChannel `com.safecircle.app/voice`. The native recognizer keeps
///   the audio engine running continuously — NO start/stop = NO "ding" sound.
///
/// **Android**: Uses `speech_to_text` package (Dart). Android doesn't have
///   the same "ding" sound issue that iOS has, so the package works fine.
///
/// ## How It Works
///
/// 1. On iOS: native code captures audio and sends recognized text to Flutter
/// 2. On Android: speech_to_text runs in Dart with AudioSession configured
/// 3. Each recognized phrase is compared against the stored activation word
/// 4. Fuzzy matching (Levenshtein distance) handles pronunciation variations
/// 5. When a match is found with >70% confidence, the alert triggers
///
/// ## Privacy
///
/// - All speech processing is done ON-DEVICE (no audio sent to servers)
/// - Uses the device's native engine (Apple/Google)
/// - No transcripts are stored unless an emergency is triggered
/// - The user can disable this at any time in Settings
class VoiceDetectionService extends ChangeNotifier {
  final SecureStorage _secureStorage;
  final VoiceprintService _voiceprintService;

  /// Legacy SharedPreferences key written by the pre-voiceprint onboarding
  /// flow (a list of paths to AAC .m4a samples that no production code has
  /// ever read). Cleaned up oneshot on first init after this build.
  static const String _legacySamplesKey = 'safecircle_voice_samples';

  /// speech_to_text — used ONLY on Android.
  final SpeechToText _speech = SpeechToText();

  /// Native voice channel — used ONLY on iOS.
  static const _nativeVoiceChannel = MethodChannel('com.safecircle.app/voice');

  /// Whether we should use the native iOS recognizer.
  bool get _useNativeRecognizer =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  bool _isInitialized = false;
  bool _isListening = false;
  bool _isEnabled = false;
  String _activationWord = '';
  String _lastRecognized = '';
  double _confidence = 0.0;
  Timer? _restartTimer;
  bool _audioSessionConfigured = false;

  /// True when the user has an activation word saved but no compatible
  /// voiceprint enrolled (e.g. legacy install before voice biometrics
  /// shipped, or a model upgrade invalidated the old profile). The
  /// detector stays disabled until [VoiceprintService.enroll] runs again.
  /// Settings UI surfaces this as a "re-train your voice" banner.
  bool _requiresEnrollment = false;

  // ── Android parallel audio buffer (Phase 5 / Path A) ────────────────
  //
  // Android's SpeechRecognizer (used by speech_to_text) opens the mic.
  // We try to also open `record`'s PCM stream in parallel, capturing the
  // same audio for voiceprint analysis. Whether this works depends on
  // the OEM (Samsung One UI, Xiaomi MIUI, OnePlus OxygenOS, etc) — many
  // devices treat the mic as exclusive and one of the two consumers will
  // fail or get silent audio. If we detect that, we stop the parallel
  // stream and fall back to the iOS-equivalent silent-skip behavior.
  // Phase 5b would replace this with a fully-native Kotlin pipeline if
  // Path A is empirically unreliable in the field.

  final AudioRecorder _bufferRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _bufferSubscription;
  bool _bufferStreamActive = false;
  Timer? _bufferHealthTimer;
  DateTime? _lastBufferChunkAt;

  /// Sliding window of the most recent ~3 s of mic audio in Int16 LE
  /// PCM bytes. Append-and-trim from a List<int> — chunks arrive every
  /// ~100 ms and are small (~3.2 KB each), so the O(N) trim cost is
  /// negligible. Migrate to a Queue<Uint8List> if Phase 7 testing
  /// flags it.
  final List<int> _androidRingBuffer = [];

  /// 3 s @ 16 kHz mono Int16 = 96000 bytes. Matches the iOS ring buffer.
  static const int _androidRingBufferBytes = 96000;

  /// Minimum bytes required to attempt voiceprint extraction (~1 s).
  /// Below this we return null from the snapshot — pipeline already
  /// rejects audio shorter than this on the embedding side.
  static const int _androidMinSnapshotBytes = 32000;

  /// Health check window: if no chunk arrives within this duration after
  /// the stream starts, we declare a mic conflict and stop the parallel
  /// stream. Some OEMs take 1-2 s to deliver the first chunk, so 5 s is
  /// a comfortable margin without pretending the silence is normal.
  static const int _bufferHealthTimeoutSeconds = 5;

  /// How similar the spoken word must be to the activation word (0.0 to 1.0).
  /// This is the TEXT-level gate. Voiceprint verification (cosine similarity
  /// against the enrolled embedding) is a separate, additional gate.
  static const double _matchThreshold = 0.70;

  /// Minimum cosine similarity between the live utterance embedding and
  /// the enrolled voiceprint to trigger an alert. Below this, the match
  /// is silently discarded — text said by someone else (TV, kids, attacker)
  /// will not fire.
  static const double _voiceprintThreshold = 0.75;

  /// Cosine similarity above which the live utterance is added to the
  /// adaptive-learning history (recomputes the aggregate embedding from
  /// the most recent 10 high-confidence samples). Strictly higher than
  /// [_voiceprintThreshold] so only confident matches refine the profile.
  static const double _adaptiveLearnThreshold = 0.85;

  /// Seconds to wait before restarting listening after a session ends.
  /// Longer delay = less "ding" sounds on platforms that still play them.
  static const int _restartDelaySeconds = 2;

  /// Max listen duration per session (longer = fewer restarts = less noise).
  static const int _listenDurationSeconds = 60;

  /// Pause detection timeout — how long silence before session ends.
  static const int _pauseForSeconds = 10;

  /// Storage key for enabled state.
  static const String _enabledKey = 'safecircle_voice_detection_enabled';

  /// Callback when activation word is detected and verified.
  /// The app should trigger emergency alert when this fires.
  VoidCallback? onActivationDetected;

  /// Callback for each recognized phrase (for debug/UI display).
  void Function(String text, double confidence)? onSpeechRecognized;

  bool get isInitialized => _isInitialized;
  bool get isListening => _isListening;
  bool get isEnabled => _isEnabled;
  String get activationWord => _activationWord;
  String get lastRecognized => _lastRecognized;
  double get confidence => _confidence;
  bool get requiresEnrollment => _requiresEnrollment;

  VoiceDetectionService({
    required SecureStorage secureStorage,
    required VoiceprintService voiceprintService,
  })  : _secureStorage = secureStorage,
        _voiceprintService = voiceprintService;

  /// Initialize the service — check if enabled and load activation word.
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Best-effort cleanup of legacy AAC voice samples written by the
      // pre-voiceprint onboarding flow. Idempotent: noop after first run.
      await _cleanupLegacySamples(prefs);

      // Load activation word
      _activationWord = await _secureStorage.getActivationWord() ?? '';
      if (_activationWord.isEmpty) {
        debugPrint('[VoiceDetection] No activation word set — skipping init');
        return;
      }

      // Voiceprint enrollment guard: if the user has an activation word but
      // no compatible voiceprint profile (legacy install, or model upgrade
      // invalidated the old profile), keep detection disabled until they
      // re-enroll. Settings UI shows a banner inviting re-training.
      final profile = await _voiceprintService.loadProfile();
      if (profile == null) {
        _requiresEnrollment = true;
        debugPrint(
          '[VoiceDetection] Activation word found but no voiceprint enrolled '
          '— detection disabled until re-enrollment',
        );
        notifyListeners();
        return;
      }

      // Check if enabled
      _isEnabled = prefs.getBool(_enabledKey) ?? false;

      if (_useNativeRecognizer) {
        // iOS: set up native MethodChannel listener
        _setupNativeListener();
        _isInitialized = true;
        debugPrint('[VoiceDetection] iOS native mode initialized. '
            'Word: "$_activationWord", Enabled: $_isEnabled');
      } else {
        // Android / Web: use speech_to_text package
        await _configureAudioSession();
        _isInitialized = await _speech.initialize(
          onError: _onError,
          onStatus: _onStatus,
          debugLogging: kDebugMode,
        );

        if (!_isInitialized) {
          debugPrint('[VoiceDetection] Speech engine failed to initialize');
          return;
        }

        debugPrint('[VoiceDetection] Android/fallback mode initialized. '
            'Word: "$_activationWord", Enabled: $_isEnabled');
      }

      // Auto-start if enabled
      if (_isEnabled) {
        await startListening();
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[VoiceDetection] Init error: $e');
    }
  }

  /// Set up the native iOS MethodChannel listener.
  /// Receives onSpeechResult and onSpeechError from SilentSpeechRecognizer.
  void _setupNativeListener() {
    _nativeVoiceChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onSpeechResult':
          final args = call.arguments as Map;
          final text = (args['text'] as String?) ?? '';
          final isFinal = (args['isFinal'] as bool?) ?? false;
          // Audio is only attached on final results (~3 s of recent
          // 16 kHz mono Int16 LE PCM). Used for voiceprint verification.
          final audio = args['audio'] as Uint8List?;
          await _handleRecognizedText(text, isFinal, audio);
          break;

        case 'onSpeechError':
          final args = call.arguments as Map;
          final error = (args['error'] as String?) ?? 'Unknown error';
          debugPrint('[VoiceDetection] Native error: $error');
          // Native side handles restart automatically
          break;
      }
    });
  }

  /// Process recognized text from either platform engine.
  ///
  /// Two-gate trigger pipeline:
  ///   1. **Text gate** (Levenshtein): the recognized text must match the
  ///      stored activation word with similarity >= [_matchThreshold].
  ///   2. **Voice gate** (cosine): on the final result, the recent audio
  ///      buffer is run through [VoiceprintService.extractEmbedding] and
  ///      compared with the enrolled profile. Cosine must be
  ///      >= [_voiceprintThreshold] to actually trigger the alert.
  ///
  /// If the text gate passes but no audio buffer is available (e.g. the
  /// Android engine path before Phase 5 wires its own ring buffer, or a
  /// race condition with an empty buffer on iOS), we **silently skip**
  /// the trigger. This is intentional security: voiceprint must always be
  /// the final gate to prevent text-only spoofing.
  Future<void> _handleRecognizedText(
    String text,
    bool isFinal,
    Uint8List? audio,
  ) async {
    final recognized = text.toLowerCase().trim();
    if (recognized.isEmpty) return;

    _lastRecognized = recognized;

    final textScore = _checkForActivationWord(recognized);

    // Below text threshold: UI feedback only, no voiceprint check.
    if (textScore < _matchThreshold) {
      _confidence = textScore;
      onSpeechRecognized?.call(recognized, textScore);
      notifyListeners();
      return;
    }

    debugPrint('[VoiceDetection] Text match "$recognized" '
        '(text score: ${textScore.toStringAsFixed(4)}, isFinal=$isFinal)');

    // Always surface the text-level confidence to the UI so partial
    // matches drive progress feedback.
    onSpeechRecognized?.call(recognized, textScore);

    // Interim results have only partial audio; wait for the final result
    // before paying the embedding cost.
    if (!isFinal) {
      _confidence = textScore;
      notifyListeners();
      return;
    }

    // Final + text match. Voiceprint is the second gate — closed if no
    // audio is attached.
    if (audio == null || audio.isEmpty) {
      debugPrint('[VoiceDetection] Final text match but no audio buffer — '
          'voiceprint cannot verify, skipping trigger');
      _confidence = textScore;
      notifyListeners();
      return;
    }

    try {
      final pcm = _uint8ToInt16Le(audio);
      final embedding = await _voiceprintService.extractEmbedding(pcm);
      final profile = await _voiceprintService.loadProfile();

      if (profile == null) {
        debugPrint('[VoiceDetection] No voiceprint profile loaded — '
            'cannot verify, skipping trigger');
        return;
      }

      final cosine = _voiceprintService.compareEmbeddings(
        embedding,
        profile.embedding,
      );
      _confidence = cosine;
      debugPrint('[VoiceDetection] Voiceprint cosine '
          '${cosine.toStringAsFixed(4)} '
          '(trigger >= $_voiceprintThreshold, '
          'adapt >= $_adaptiveLearnThreshold)');
      onSpeechRecognized?.call(recognized, cosine);

      if (cosine >= _voiceprintThreshold) {
        debugPrint(
          '[VoiceDetection] *** ACTIVATION TRIGGERED (voice verified) ***',
        );
        _triggerActivation();

        // Adaptive learning: high-confidence match feeds back into the
        // profile. Fire-and-forget — do not block the trigger path.
        if (cosine >= _adaptiveLearnThreshold) {
          unawaited(
            _voiceprintService.updateProfileWithNewSample(embedding),
          );
        }
      } else {
        debugPrint('[VoiceDetection] Voice mismatch — silent reject '
            '(cosine ${cosine.toStringAsFixed(4)} '
            '< $_voiceprintThreshold)');
      }
    } catch (e, stack) {
      debugPrint(
        '[VoiceDetection] Voiceprint pipeline error: $e\n$stack',
      );
    }

    notifyListeners();
  }

  /// Convert little-endian Int16 PCM bytes (as delivered by the native
  /// ring buffer) to a typed [Int16List] suitable for
  /// [VoiceprintService.extractEmbedding]. Uses [ByteData] to avoid
  /// alignment requirements on the source [Uint8List].
  static Int16List _uint8ToInt16Le(Uint8List bytes) {
    final samples = Int16List(bytes.length ~/ 2);
    final bd = ByteData.sublistView(bytes);
    for (int i = 0; i < samples.length; i++) {
      samples[i] = bd.getInt16(i * 2, Endian.little);
    }
    return samples;
  }

  /// Configure AudioSession to suppress system sounds (Android fallback only).
  Future<void> _configureAudioSession() async {
    if (_audioSessionConfigured) return;

    try {
      final session = await AudioSession.instance;

      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker |
            AVAudioSessionCategoryOptions.duckOthers |
            AVAudioSessionCategoryOptions.allowBluetooth |
            AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.measurement,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions:
            AVAudioSessionSetActiveOptions.notifyOthersOnDeactivation,
        androidAudioAttributes: const AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
          flags: AndroidAudioFlags.none,
        ),
        androidAudioFocusGainType:
            AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ));

      await session.setActive(true);
      _audioSessionConfigured = true;

      debugPrint('[VoiceDetection] AudioSession configured for silent mode');
    } catch (e) {
      debugPrint('[VoiceDetection] AudioSession config error: $e '
          '(will continue with default — may have system sounds)');
    }
  }

  /// Enable voice detection and start listening.
  Future<void> enable() async {
    _isEnabled = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, true);

    if (_isInitialized && !_isListening) {
      await startListening();
    }
    notifyListeners();
  }

  /// Disable voice detection and stop listening.
  Future<void> disable() async {
    _isEnabled = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);

    await stopListening();
    notifyListeners();
  }

  /// Update the activation word.
  Future<void> updateActivationWord(String word) async {
    _activationWord = word.trim().toLowerCase();
    await _secureStorage.setActivationWord(_activationWord);
    debugPrint('[VoiceDetection] Activation word updated: "$_activationWord"');
    notifyListeners();
  }

  /// Start continuous listening.
  /// iOS: calls native SilentSpeechRecognizer (zero sound).
  /// Android: uses speech_to_text package.
  Future<void> startListening() async {
    if (!_isInitialized || _isListening) return;
    if (_activationWord.isEmpty) return;

    try {
      if (_useNativeRecognizer) {
        // iOS native — completely silent
        final started = await _nativeVoiceChannel
            .invokeMethod<bool>('startVoiceDetection') ?? false;

        if (started) {
          _isListening = true;
          debugPrint('[VoiceDetection] iOS native listening started (silent)');
        } else {
          debugPrint('[VoiceDetection] iOS native failed to start');
          _scheduleRestart();
        }
      } else {
        // Android fallback — speech_to_text
        await _configureAudioSession();
        _isListening = true;

        await _speech.listen(
          onResult: _onSpeechResult,
          listenFor: const Duration(seconds: _listenDurationSeconds),
          pauseFor: const Duration(seconds: _pauseForSeconds),
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: false,
        );

        // Try to also open a parallel PCM stream for voiceprint audio.
        // Best-effort: failure leaves voice activation dormant on Android
        // (silent skip in _handleRecognizedText) until Phase 5b ships.
        await _startAndroidBufferStream();

        debugPrint('[VoiceDetection] Android listening started '
            '(${_listenDurationSeconds}s session)');
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[VoiceDetection] Start error: $e');
      _isListening = false;
      _scheduleRestart();
    }
  }

  /// Stop listening.
  Future<void> stopListening() async {
    _restartTimer?.cancel();
    _restartTimer = null;

    if (_isListening) {
      if (_useNativeRecognizer) {
        await _nativeVoiceChannel.invokeMethod('stopVoiceDetection');
      } else {
        await _speech.stop();
        await _stopAndroidBufferStream();
      }
      _isListening = false;
      debugPrint('[VoiceDetection] Listening stopped');
      notifyListeners();
    }
  }

  // ── Speech Callbacks (Android fallback only) ─────

  void _onSpeechResult(SpeechRecognitionResult result) {
    final recognized = result.recognizedWords.toLowerCase().trim();
    if (recognized.isEmpty) return;
    // Snapshot the parallel mic buffer only on final results — matches
    // iOS behavior and avoids the copy cost on every interim event.
    // If the parallel stream isn't running (Phase 5 Path A failed), the
    // snapshot returns null and _handleRecognizedText silent-skips the
    // trigger via its security gate.
    final audio = result.finalResult ? _snapshotAndroidBuffer() : null;
    _handleRecognizedText(recognized, result.finalResult, audio);
  }

  void _onError(SpeechRecognitionError error) {
    debugPrint('[VoiceDetection] Error: ${error.errorMsg} '
        '(permanent: ${error.permanent})');

    if (error.permanent) {
      _isListening = false;
      notifyListeners();
    }

    if (_isEnabled) {
      _scheduleRestart();
    }
  }

  void _onStatus(String status) {
    debugPrint('[VoiceDetection] Status: $status');

    if (status == 'notListening' || status == 'done') {
      _isListening = false;
      notifyListeners();

      if (_isEnabled) {
        _scheduleRestart();
      }
    }
  }

  // ── Matching Engine ──────────────────────────────

  /// Check if the activation word appears in the recognized text.
  /// Returns a confidence score between 0.0 and 1.0.
  double _checkForActivationWord(String text) {
    final target = _activationWord.toLowerCase();
    final words = text.toLowerCase();

    // 1. Exact match
    if (words.contains(target)) return 1.0;

    // 2. Word-by-word fuzzy match
    final targetWords = target.split(RegExp(r'\s+'));
    final spokenWords = words.split(RegExp(r'\s+'));

    // Check if any subsequence of spoken words matches the target
    double bestScore = 0.0;

    for (int i = 0; i <= spokenWords.length - targetWords.length; i++) {
      double totalScore = 0;
      for (int j = 0; j < targetWords.length; j++) {
        final sim = _stringSimilarity(
          targetWords[j],
          spokenWords[i + j],
        );
        totalScore += sim;
      }
      final avgScore = totalScore / targetWords.length;
      if (avgScore > bestScore) bestScore = avgScore;
    }

    // 3. Also check each spoken word individually against the full target
    // (for single-word activation words)
    if (targetWords.length == 1) {
      for (final word in spokenWords) {
        final sim = _stringSimilarity(target, word);
        if (sim > bestScore) bestScore = sim;
      }
    }

    return bestScore;
  }

  /// Calculate similarity between two strings using Levenshtein distance.
  /// Returns 0.0 (completely different) to 1.0 (identical).
  static double _stringSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final maxLen = math.max(a.length, b.length);
    final distance = _levenshteinDistance(a, b);

    return 1.0 - (distance / maxLen);
  }

  /// Levenshtein distance between two strings.
  static int _levenshteinDistance(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    List<int> previousRow = List.generate(b.length + 1, (i) => i);
    List<int> currentRow = List.filled(b.length + 1, 0);

    for (int i = 0; i < a.length; i++) {
      currentRow[0] = i + 1;
      for (int j = 0; j < b.length; j++) {
        final cost = a[i] == b[j] ? 0 : 1;
        currentRow[j + 1] = [
          currentRow[j] + 1,
          previousRow[j + 1] + 1,
          previousRow[j] + cost,
        ].reduce(math.min);
      }
      final temp = previousRow;
      previousRow = currentRow;
      currentRow = temp;
    }

    return previousRow[b.length];
  }

  // ── Trigger ──────────────────────────────────────

  void _triggerActivation() {
    // Stop listening during emergency
    stopListening();

    // Fire the callback — the app layer handles the actual alert
    onActivationDetected?.call();
  }

  // ── Restart Logic ────────────────────────────────

  void _scheduleRestart() {
    _restartTimer?.cancel();
    _restartTimer = Timer(
      const Duration(seconds: _restartDelaySeconds),
      () {
        if (_isEnabled && !_isListening) {
          startListening();
        }
      },
    );
  }

  // ── Legacy cleanup ───────────────────────────────────────────────

  /// Deletes the AAC .m4a voice samples written by the pre-voiceprint
  /// onboarding flow (and clears the SharedPreferences key that pointed
  /// to them). The samples were never used by any production code path
  /// — they're orphan files leaking ~80 KB of biometric audio per user.
  ///
  /// Best-effort: missing files, permission errors, and other I/O issues
  /// are swallowed silently. Idempotent: after the first successful run
  /// the SharedPreferences key is removed and subsequent calls return
  /// immediately.
  Future<void> _cleanupLegacySamples(SharedPreferences prefs) async {
    final samples = prefs.getStringList(_legacySamplesKey);
    if (samples == null || samples.isEmpty) return;

    int deleted = 0;
    for (final path in samples) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          deleted++;
        }
      } catch (_) {
        // Ignore — best-effort cleanup.
      }
    }

    await prefs.remove(_legacySamplesKey);
    if (deleted > 0) {
      debugPrint('[VoiceDetection] Cleaned up $deleted legacy voice samples');
    }
  }

  // ── Android parallel buffer stream (Phase 5 / Path A) ───────────────

  /// Open `record`'s PCM 16 kHz mono stream and start filling the
  /// sliding window. Best-effort: failures (mic conflict with
  /// SpeechRecognizer, OEM exclusivity, permission edge cases) are logged
  /// and the parallel stream stays off — voice activation simply remains
  /// dormant on Android until Phase 5b ships a fully-native pipeline.
  Future<void> _startAndroidBufferStream() async {
    if (_bufferStreamActive) return;
    _androidRingBuffer.clear();

    try {
      final stream = await _bufferRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _bufferStreamActive = true;
      _lastBufferChunkAt = DateTime.now();

      _bufferSubscription = stream.listen(
        (chunk) {
          _lastBufferChunkAt = DateTime.now();
          _appendToAndroidRingBuffer(chunk);
        },
        onError: (Object e) {
          debugPrint('[VoiceDetection] Android buffer stream error: $e');
          // Fire-and-forget cleanup; don't block the listener thread.
          unawaited(_stopAndroidBufferStream());
        },
        onDone: () {
          debugPrint('[VoiceDetection] Android buffer stream closed');
          _bufferStreamActive = false;
        },
      );

      // Health check: if no chunks arrive within the timeout, declare a
      // mic conflict and stop the parallel stream. Without this, a
      // silently-broken stream would keep us thinking voice activation
      // is working when it isn't.
      _bufferHealthTimer = Timer(
        const Duration(seconds: _bufferHealthTimeoutSeconds),
        () {
          final last = _lastBufferChunkAt;
          if (last == null ||
              DateTime.now().difference(last).inSeconds >=
                  _bufferHealthTimeoutSeconds) {
            debugPrint(
              '[VoiceDetection] Android buffer silent for '
              '${_bufferHealthTimeoutSeconds}s — mic conflict suspected, '
              'stopping parallel stream',
            );
            debugPrint(
              '[VoiceDetection] Voice activation will remain dormant on '
              'Android (Phase 5b needed)',
            );
            unawaited(_stopAndroidBufferStream());
          }
        },
      );

      debugPrint(
        '[VoiceDetection] Android parallel buffer stream started',
      );
    } catch (e, stack) {
      debugPrint(
        '[VoiceDetection] Failed to start Android buffer stream: $e\n$stack',
      );
      debugPrint(
        '[VoiceDetection] Voice activation will remain dormant on Android '
        '(Phase 5b needed)',
      );
      _bufferStreamActive = false;
    }
  }

  /// Append a chunk of Int16 LE PCM bytes to the sliding window, trimming
  /// from the front so the buffer never exceeds [_androidRingBufferBytes].
  void _appendToAndroidRingBuffer(Uint8List chunk) {
    _androidRingBuffer.addAll(chunk);
    final overflow = _androidRingBuffer.length - _androidRingBufferBytes;
    if (overflow > 0) {
      _androidRingBuffer.removeRange(0, overflow);
    }
  }

  /// Snapshot the sliding window as a fresh Uint8List, or null if there's
  /// less than ~1 s of audio captured (the embedding pipeline rejects
  /// shorter clips). Returns a copy — caller can hold the reference even
  /// after subsequent appends mutate the underlying list.
  Uint8List? _snapshotAndroidBuffer() {
    if (_androidRingBuffer.length < _androidMinSnapshotBytes) return null;
    return Uint8List.fromList(_androidRingBuffer);
  }

  /// Stop the parallel buffer stream and clear the sliding window.
  /// Idempotent: safe to call multiple times. Failures during stop are
  /// swallowed (the recorder may already be in an error state).
  Future<void> _stopAndroidBufferStream() async {
    _bufferHealthTimer?.cancel();
    _bufferHealthTimer = null;

    final sub = _bufferSubscription;
    _bufferSubscription = null;
    if (sub != null) {
      try {
        await sub.cancel();
      } catch (_) {}
    }

    if (_bufferStreamActive) {
      try {
        await _bufferRecorder.stop();
      } catch (_) {}
    }

    _bufferStreamActive = false;
    _lastBufferChunkAt = null;
    _androidRingBuffer.clear();
  }

  @override
  void dispose() {
    _restartTimer?.cancel();
    _bufferHealthTimer?.cancel();
    _speech.stop();
    unawaited(_stopAndroidBufferStream());
    _bufferRecorder.dispose();
    super.dispose();
  }
}
