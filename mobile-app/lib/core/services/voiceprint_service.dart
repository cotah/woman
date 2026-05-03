import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/voiceprint_profile.dart';
import '../storage/secure_storage.dart';
import '../utils/mel_filterbank.dart';

/// Lifecycle states for the voiceprint engine.
enum VoiceprintStatus {
  /// initialize() has not been called yet.
  uninitialized,

  /// Model is loading or warming up.
  loading,

  /// Model is loaded, warmed up, ready for inference.
  ready,

  /// Loading or warmup failed; voice biometrics is unavailable for the
  /// rest of the session. Inspect [errorMessage].
  error,
}

/// On-device speaker verification engine.
///
/// Phase 1 loaded the TFLite interpreter and ran a warmup inference.
/// Phase 2 (this revision) wires the full pipeline:
///
///   - [extractEmbedding]: PCM 16 kHz mono → log-mel filterbank → TFLite
///     inference → L2-normalized 256-dim embedding.
///   - [compareEmbeddings]: cosine similarity (= dot product since both
///     inputs are L2-normalized) between two embeddings.
///   - [enroll]: extract embeddings from N samples, take the median
///     element-wise, persist via [SecureStorage] under
///     [_profileStorageKey].
///   - [loadProfile]: read and validate the saved profile (model hash
///     check forces re-enrollment after a model upgrade).
///   - [updateProfileWithNewSample]: adaptive learning hook (will be
///     called from [VoiceDetectionService] in a later phase whenever a
///     match exceeds the high-confidence threshold).
///
/// The model expects a transposed FBANK input shape:
///   [1, 80, T] (NWC) — not [1, T, 80] like the source ONNX. This is a
///   side effect of onnx2tf's NCW->NWC convention. See
///   tools/convert_model.py for details. [MelFilterbank.extract] already
///   produces the [80, T] layout, so we only need to add the batch dim.
///
/// Failure modes are isolated: if the model fails to load or any inference
/// throws, [status] becomes [VoiceprintStatus.error] and the rest of the
/// app keeps working without voice biometrics.
class VoiceprintService extends ChangeNotifier {
  /// Asset path of the bundled TFLite model. Registered in pubspec.yaml
  /// under flutter > assets.
  static const String modelAssetPath =
      'assets/models/voxceleb_resnet34_LM.tflite';

  /// Number of mel filterbank bins the model expects.
  static const int fbankDim = 80;

  /// Output speaker embedding dimensionality.
  static const int embeddingDim = 256;

  /// Default time frames for warmup. Real inference can resize to any T.
  /// 200 frames @ 10 ms hop ≈ 2 s of audio.
  static const int warmupTimeFrames = 200;

  /// SecureStorage key for the persisted [VoiceprintProfile]. Versioned
  /// so future schema changes can coexist with old installs.
  static const String _profileStorageKey = 'voiceprint_profile_v1';

  final SecureStorage _secureStorage;

  Interpreter? _interpreter;
  MelFilterbank? _melFilterbank;
  VoiceprintStatus _status = VoiceprintStatus.uninitialized;
  Duration? _loadDuration;
  Duration? _warmupDuration;
  String? _errorMessage;

  VoiceprintService({required SecureStorage secureStorage})
      : _secureStorage = secureStorage;

  VoiceprintStatus get status => _status;
  Duration? get loadDuration => _loadDuration;
  Duration? get warmupDuration => _warmupDuration;
  String? get errorMessage => _errorMessage;
  bool get isReady => _status == VoiceprintStatus.ready;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  /// Loads the interpreter from assets, builds the mel filterbank, and
  /// runs one warmup inference. Safe to call multiple times — subsequent
  /// calls return early.
  Future<void> initialize() async {
    if (_status != VoiceprintStatus.uninitialized) return;
    _status = VoiceprintStatus.loading;
    notifyListeners();

    try {
      final loadStopwatch = Stopwatch()..start();
      _interpreter = await Interpreter.fromAsset(modelAssetPath);
      _melFilterbank = MelFilterbank();
      loadStopwatch.stop();
      _loadDuration = loadStopwatch.elapsed;
      debugPrint(
        '[Voiceprint] Model + filterbank loaded in '
        '${_loadDuration!.inMilliseconds}ms',
      );

      // TFLite shape is [1, 80, T] (NWC), transposed from the ONNX
      // [1, T, 80] by onnx2tf during conversion.
      _interpreter!.resizeInputTensor(0, [1, fbankDim, warmupTimeFrames]);
      _interpreter!.allocateTensors();

      final input = List.generate(
        1,
        (_) => List.generate(
          fbankDim,
          (_) => List<double>.filled(warmupTimeFrames, 0.0),
        ),
      );
      final output = List.generate(
        1,
        (_) => List<double>.filled(embeddingDim, 0.0),
      );

      final warmupStopwatch = Stopwatch()..start();
      _interpreter!.run(input, output);
      warmupStopwatch.stop();
      _warmupDuration = warmupStopwatch.elapsed;
      debugPrint(
        '[Voiceprint] Warmup inference in '
        '${_warmupDuration!.inMilliseconds}ms',
      );

      _status = VoiceprintStatus.ready;
      _errorMessage = null;
      notifyListeners();
    } catch (e, stack) {
      _errorMessage = e.toString();
      _status = VoiceprintStatus.error;
      debugPrint('[Voiceprint] Init failed: $e\n$stack');
      try {
        _interpreter?.close();
      } catch (_) {}
      _interpreter = null;
      _melFilterbank = null;
      notifyListeners();
    }
  }

  // ── Inference ─────────────────────────────────────────────────────────

  /// Computes a 256-dim L2-normalized speaker embedding from PCM 16 kHz
  /// mono audio. Throws [ArgumentError] if the audio is shorter than
  /// [kMinPcmSamples] (1 s); throws [StateError] if the service is not
  /// ready.
  ///
  /// This is the hot path: ~30-40 ms STFT + ~10-30 ms TFLite inference on
  /// a mid-range mobile CPU. Acceptable to run on the main isolate for
  /// enrollment (3 sequential calls) and per-utterance verification
  /// (called only when a candidate activation word is detected).
  Future<Float32List> extractEmbedding(Int16List pcm16k) async {
    if (!isReady || _interpreter == null || _melFilterbank == null) {
      throw StateError('VoiceprintService not initialized (status=$_status)');
    }

    // 1. Compute log-mel filterbank: Float32List length = 80 * T,
    //    row-major (mel-bin first).
    final melFlat = _melFilterbank!.extract(pcm16k);
    final t = melFlat.length ~/ fbankDim;

    // 2. Resize TFLite input to [1, 80, T] and allocate.
    _interpreter!.resizeInputTensor(0, [1, fbankDim, t]);
    _interpreter!.allocateTensors();

    // 3. Reshape flat Float32List → nested List the interpreter expects.
    final input = List.generate(
      1,
      (_) => List.generate(
        fbankDim,
        (m) => List<double>.generate(t, (frame) => melFlat[m * t + frame]),
      ),
    );

    final output = List.generate(
      1,
      (_) => List<double>.filled(embeddingDim, 0.0),
    );

    // 4. Run inference.
    _interpreter!.run(input, output);

    // 5. Convert nested → Float32List + L2 normalize.
    final embedding = Float32List(embeddingDim);
    for (int i = 0; i < embeddingDim; i++) {
      embedding[i] = output[0][i];
    }
    return _normalizeL2(embedding);
  }

  /// Cosine similarity between two L2-normalized embeddings. Since both
  /// are unit vectors, this reduces to a plain dot product. Range
  /// [-1, 1]; same speaker typically lands in [0.4, 1.0].
  ///
  /// Throws [ArgumentError] if dimensions don't match.
  double compareEmbeddings(Float32List a, Float32List b) {
    if (a.length != b.length) {
      throw ArgumentError(
        'Embedding dim mismatch: ${a.length} vs ${b.length}',
      );
    }
    double dot = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }
    return dot;
  }

  // ── Enrollment & profile management ──────────────────────────────────

  /// Enrolls a new voiceprint from [samples] (minimum 3). Computes one
  /// embedding per sample, takes the median element-wise (more robust to
  /// outliers than mean), re-normalizes L2, and persists the resulting
  /// [VoiceprintProfile] to [SecureStorage]. Returns the new profile.
  ///
  /// Replaces any existing profile.
  Future<VoiceprintProfile> enroll(List<Int16List> samples) async {
    if (!isReady) {
      throw StateError('VoiceprintService not initialized (status=$_status)');
    }
    if (samples.length < 3) {
      throw ArgumentError(
        'Need at least 3 samples for enrollment, got ${samples.length}',
      );
    }

    final embeddings = <Float32List>[];
    for (int i = 0; i < samples.length; i++) {
      debugPrint(
        '[Voiceprint] Extracting enrollment embedding ${i + 1}/${samples.length}',
      );
      embeddings.add(await extractEmbedding(samples[i]));
    }

    final aggregated = _medianEmbedding(embeddings);

    final profile = VoiceprintProfile(
      embedding: aggregated,
      history: List.unmodifiable(embeddings),
      modelHash: VoiceprintProfile.currentModelHash,
      updatedAt: DateTime.now(),
      version: VoiceprintProfile.currentVersion,
    );

    await _saveProfile(profile);
    debugPrint('[Voiceprint] Enrolled with ${samples.length} samples');
    notifyListeners();
    return profile;
  }

  /// Loads the saved profile, or returns null if none exists, the JSON is
  /// corrupted, or the model hash no longer matches (forcing
  /// re-enrollment after a model upgrade).
  ///
  /// Never throws — failures are logged and surfaced as null.
  Future<VoiceprintProfile?> loadProfile() async {
    try {
      final raw = await _secureStorage.read(_profileStorageKey);
      if (raw == null) return null;

      final json = jsonDecode(raw) as Map<String, dynamic>;
      final profile = VoiceprintProfile.fromJson(json);

      if (!profile.isCompatibleWithCurrentModel) {
        debugPrint(
          '[Voiceprint] WARNING: saved profile model hash '
          '${profile.modelHash.substring(0, 8)}... does not match current '
          '${VoiceprintProfile.currentModelHash.substring(0, 8)}.... '
          'Re-enrollment required.',
        );
        return null;
      }

      return profile;
    } catch (e) {
      debugPrint('[Voiceprint] Failed to load profile: $e — returning null');
      return null;
    }
  }

  /// Adaptive-learning hook. Adds [newEmbedding] to the saved profile's
  /// history (trimming to [VoiceprintProfile.maxHistorySize]), recomputes
  /// the median aggregate, and persists. No-op if no profile exists.
  ///
  /// Called from the runtime verification path (later phase) when a
  /// detected utterance scores above the high-confidence threshold (0.85).
  Future<void> updateProfileWithNewSample(Float32List newEmbedding) async {
    final existing = await loadProfile();
    if (existing == null) {
      debugPrint(
        '[Voiceprint] No existing profile — skipping adaptive update',
      );
      return;
    }

    final newHistory = [...existing.history, newEmbedding];
    final trimmed = newHistory.length > VoiceprintProfile.maxHistorySize
        ? newHistory.sublist(
            newHistory.length - VoiceprintProfile.maxHistorySize,
          )
        : newHistory;

    final aggregated = _medianEmbedding(trimmed);

    final updated = VoiceprintProfile(
      embedding: aggregated,
      history: List.unmodifiable(trimmed),
      modelHash: VoiceprintProfile.currentModelHash,
      updatedAt: DateTime.now(),
      version: VoiceprintProfile.currentVersion,
    );

    await _saveProfile(updated);
    debugPrint(
      '[Voiceprint] Profile updated with new sample '
      '(history size: ${trimmed.length})',
    );
  }

  /// Removes the saved profile. Used by re-enrollment flow and account
  /// deletion (LGPD). Idempotent.
  Future<void> deleteProfile() async {
    try {
      await _secureStorage.delete(_profileStorageKey);
      debugPrint('[Voiceprint] Profile deleted');
    } catch (e) {
      debugPrint('[Voiceprint] Failed to delete profile: $e');
    }
    notifyListeners();
  }

  // ── Internals ─────────────────────────────────────────────────────────

  Future<void> _saveProfile(VoiceprintProfile profile) async {
    await _secureStorage.write(
      _profileStorageKey,
      jsonEncode(profile.toJson()),
    );
  }

  /// Element-wise median across [embeddings], then L2 re-normalized.
  /// Median doesn't preserve unit norm, so the renorm is mandatory before
  /// the result is used in cosine comparisons.
  static Float32List _medianEmbedding(List<Float32List> embeddings) {
    if (embeddings.isEmpty) {
      throw ArgumentError('Cannot compute median of empty list');
    }
    final n = embeddings.length;
    final dim = embeddings.first.length;
    final result = Float32List(dim);
    final buffer = List<double>.filled(n, 0);

    for (int d = 0; d < dim; d++) {
      for (int i = 0; i < n; i++) {
        buffer[i] = embeddings[i][d];
      }
      buffer.sort();
      result[d] = n.isOdd
          ? buffer[n ~/ 2]
          : (buffer[n ~/ 2 - 1] + buffer[n ~/ 2]) / 2;
    }
    return _normalizeL2(result);
  }

  /// In-place-style L2 normalization. Returns a new Float32List with
  /// ‖result‖₂ == 1, or the original (untouched) array if its norm is
  /// effectively zero (avoids division by zero).
  static Float32List _normalizeL2(Float32List arr) {
    double sumSq = 0;
    for (int i = 0; i < arr.length; i++) {
      sumSq += arr[i] * arr[i];
    }
    final norm = math.sqrt(sumSq);
    if (norm < 1e-12) return arr;
    final result = Float32List(arr.length);
    for (int i = 0; i < arr.length; i++) {
      result[i] = arr[i] / norm;
    }
    return result;
  }

  @override
  void dispose() {
    try {
      _interpreter?.close();
    } catch (_) {}
    _interpreter = null;
    _melFilterbank = null;
    super.dispose();
  }
}
