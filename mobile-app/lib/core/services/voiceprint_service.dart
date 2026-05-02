import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

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
/// Phase 1 (this file) loads the Wespeaker ResNet34-LM TFLite model from
/// assets and runs one warmup inference with zeros to amortize the
/// first-run JIT cost. Subsequent phases will add:
///   - Phase 2: log-mel feature extraction + extractEmbedding() + cosine
///     comparison
///   - Phase 3: enrollment flow integrated with onboarding
///   - Later: adaptive learning, Sentry instrumentation
///
/// The model expects a transposed FBANK input shape:
///   [1, 80, T] (NWC) — not [1, T, 80] like the source ONNX. This is a
///   side effect of onnx2tf's NCW->NWC convention. See tools/convert_model.py
///   for details. The Dart preprocessing pipeline (Phase 2) must transpose
///   accordingly.
///
/// Failure modes are isolated: if the model fails to load (corrupt asset,
/// unsupported platform, OOM), [status] becomes [VoiceprintStatus.error]
/// and the rest of the app keeps working without voice biometrics.
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

  Interpreter? _interpreter;
  VoiceprintStatus _status = VoiceprintStatus.uninitialized;
  Duration? _loadDuration;
  Duration? _warmupDuration;
  String? _errorMessage;

  VoiceprintStatus get status => _status;
  Duration? get loadDuration => _loadDuration;
  Duration? get warmupDuration => _warmupDuration;
  String? get errorMessage => _errorMessage;
  bool get isReady => _status == VoiceprintStatus.ready;

  /// Loads the interpreter from assets and runs one warmup inference.
  /// Safe to call multiple times — subsequent calls return early.
  Future<void> initialize() async {
    if (_status != VoiceprintStatus.uninitialized) return;
    _status = VoiceprintStatus.loading;
    notifyListeners();

    try {
      final loadStopwatch = Stopwatch()..start();
      _interpreter = await Interpreter.fromAsset(modelAssetPath);
      loadStopwatch.stop();
      _loadDuration = loadStopwatch.elapsed;
      debugPrint(
        '[Voiceprint] Model loaded in ${_loadDuration!.inMilliseconds}ms',
      );

      // Resize to the warmup shape and allocate tensors.
      // TFLite shape is [1, 80, T] (NWC), transposed from the ONNX
      // [1, T, 80] by onnx2tf during conversion.
      _interpreter!.resizeInputTensor(0, [1, fbankDim, warmupTimeFrames]);
      _interpreter!.allocateTensors();

      // Warmup inference with zeros. Output buffer must match
      // [1, embeddingDim] declared by the model.
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
      notifyListeners();
    }
  }

  // ── Phase 2 placeholders ──────────────────────────────────────────────

  /// Computes a 256-dim speaker embedding from PCM 16 kHz mono audio.
  /// IMPLEMENTED IN PHASE 2 (mel filterbank + transpose + interpreter.run).
  Future<Float32List> extractEmbedding(Int16List pcm16k) async {
    throw UnimplementedError(
      'extractEmbedding: implemented in Phase 2 (mel + inference pipeline)',
    );
  }

  /// Cosine similarity between two embeddings, range [-1, 1] (normalized
  /// embeddings yield [0, 1]).
  /// IMPLEMENTED IN PHASE 2.
  double compareEmbeddings(Float32List a, Float32List b) {
    throw UnimplementedError(
      'compareEmbeddings: implemented in Phase 2',
    );
  }

  @override
  void dispose() {
    try {
      _interpreter?.close();
    } catch (_) {}
    _interpreter = null;
    super.dispose();
  }
}
