import 'dart:async';
import 'dart:math' as math;
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/secure_storage.dart';

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

  /// How similar the spoken word must be to the activation word (0.0 to 1.0).
  static const double _matchThreshold = 0.70;

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

  VoiceDetectionService({required SecureStorage secureStorage})
      : _secureStorage = secureStorage;

  /// Initialize the service — check if enabled and load activation word.
  Future<void> initialize() async {
    try {
      // Load activation word
      _activationWord = await _secureStorage.getActivationWord() ?? '';
      if (_activationWord.isEmpty) {
        debugPrint('[VoiceDetection] No activation word set — skipping init');
        return;
      }

      // Check if enabled
      final prefs = await SharedPreferences.getInstance();
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
          _handleRecognizedText(text, isFinal);
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

  /// Process recognized text (shared between iOS native and Android fallback).
  void _handleRecognizedText(String text, bool isFinal) {
    final recognized = text.toLowerCase().trim();
    if (recognized.isEmpty) return;

    _lastRecognized = recognized;

    final matchResult = _checkForActivationWord(recognized);

    if (matchResult > 0) {
      _confidence = matchResult;
      debugPrint('[VoiceDetection] MATCH! "$recognized" '
          '(confidence: ${(matchResult * 100).toStringAsFixed(1)}%)');

      onSpeechRecognized?.call(recognized, matchResult);

      if (matchResult >= _matchThreshold) {
        debugPrint('[VoiceDetection] *** ACTIVATION TRIGGERED ***');
        _triggerActivation();
      }
    } else {
      _confidence = 0.0;
      onSpeechRecognized?.call(recognized, 0.0);
    }

    notifyListeners();
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
    _handleRecognizedText(recognized, result.finalResult);
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

  @override
  void dispose() {
    _restartTimer?.cancel();
    _speech.stop();
    super.dispose();
  }
}
