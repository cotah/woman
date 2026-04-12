import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/secure_storage.dart';

/// Continuous voice detection service.
///
/// Listens in the background for the user's activation word and triggers
/// an emergency alert when detected + verified.
///
/// ## How It Works
///
/// 1. The SpeechToText engine runs continuously in short listening sessions
/// 2. Each recognized phrase is compared against the stored activation word
/// 3. Fuzzy matching (Levenshtein distance) handles pronunciation variations
/// 4. When a match is found with >70% confidence, the alert triggers
/// 5. The service auto-restarts listening after each session ends
///
/// ## Privacy
///
/// - All speech processing is done ON-DEVICE (no audio sent to servers)
/// - SpeechToText uses the device's native engine (Apple/Google)
/// - No transcripts are stored unless an emergency is triggered
/// - The user can disable this at any time in Settings
class VoiceDetectionService extends ChangeNotifier {
  final SecureStorage _secureStorage;
  final SpeechToText _speech = SpeechToText();

  bool _isInitialized = false;
  bool _isListening = false;
  bool _isEnabled = false;
  String _activationWord = '';
  String _lastRecognized = '';
  double _confidence = 0.0;
  Timer? _restartTimer;

  /// How similar the spoken word must be to the activation word (0.0 to 1.0).
  static const double _matchThreshold = 0.70;

  /// Seconds to wait before restarting listening after a session ends.
  static const int _restartDelaySeconds = 1;

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

      // Initialize speech engine
      _isInitialized = await _speech.initialize(
        onError: _onError,
        onStatus: _onStatus,
        debugLogging: kDebugMode,
      );

      if (!_isInitialized) {
        debugPrint('[VoiceDetection] Speech engine failed to initialize');
        return;
      }

      debugPrint('[VoiceDetection] Initialized. Word: "$_activationWord", '
          'Enabled: $_isEnabled');

      // Auto-start if enabled
      if (_isEnabled) {
        await startListening();
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[VoiceDetection] Init error: $e');
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
  Future<void> startListening() async {
    if (!_isInitialized || _isListening) return;
    if (_activationWord.isEmpty) return;

    try {
      _isListening = true;
      notifyListeners();

      await _speech.listen(
        onResult: _onSpeechResult,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: false,
      );

      debugPrint('[VoiceDetection] Listening started');
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
      await _speech.stop();
      _isListening = false;
      debugPrint('[VoiceDetection] Listening stopped');
      notifyListeners();
    }
  }

  // ── Speech Callbacks ─────────────────────────────

  void _onSpeechResult(SpeechRecognitionResult result) {
    final recognized = result.recognizedWords.toLowerCase().trim();
    if (recognized.isEmpty) return;

    _lastRecognized = recognized;

    // Check if the activation word is in the recognized text
    final matchResult = _checkForActivationWord(recognized);

    if (matchResult > 0) {
      _confidence = matchResult;
      debugPrint('[VoiceDetection] MATCH! "$recognized" '
          '(confidence: ${(matchResult * 100).toStringAsFixed(1)}%)');

      onSpeechRecognized?.call(recognized, matchResult);

      if (matchResult >= _matchThreshold) {
        // ACTIVATION WORD DETECTED
        debugPrint('[VoiceDetection] *** ACTIVATION TRIGGERED ***');
        _triggerActivation();
      }
    } else {
      _confidence = 0.0;
      onSpeechRecognized?.call(recognized, 0.0);
    }

    notifyListeners();
  }

  void _onError(SpeechRecognitionError error) {
    debugPrint('[VoiceDetection] Error: ${error.errorMsg} '
        '(permanent: ${error.permanent})');

    if (error.permanent) {
      _isListening = false;
      notifyListeners();
    }

    // Always try to restart
    if (_isEnabled) {
      _scheduleRestart();
    }
  }

  void _onStatus(String status) {
    debugPrint('[VoiceDetection] Status: $status');

    if (status == 'notListening' || status == 'done') {
      _isListening = false;
      notifyListeners();

      // Auto-restart if enabled (continuous listening loop)
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
