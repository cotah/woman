import 'dart:convert';
import 'dart:typed_data';

/// Persisted speaker voiceprint for a single user.
///
/// Holds the aggregate L2-normalized embedding (used for runtime cosine
/// comparison) plus the history of recent enrollment samples (used by
/// adaptive learning to recompute the aggregate as more high-confidence
/// matches accumulate).
///
/// Stored on-device only — never synchronized to the backend. Voiceprints
/// are biometric data with LGPD/GDPR implications; trading device-swap
/// recovery for privacy is the deliberate trade-off.
///
/// Schema is versioned via [version] to allow future migrations without
/// breaking existing installs.
class VoiceprintProfile {
  /// Schema version. Bump when the wire format changes.
  static const int currentVersion = 1;

  /// SHA256 of the bundled .tflite the embeddings were computed with.
  /// If a future model upgrade changes this hash, saved profiles become
  /// incompatible and the user must re-enroll. Computed at build time
  /// via tools/convert_model.py output:
  ///
  ///     sha256sum mobile-app/assets/models/voxceleb_resnet34_LM.tflite
  static const String currentModelHash =
      '32e79eba27448cb6d20993fb6c1fc050c5c13e4c99245c77eec695e64da0c628';

  /// Maximum number of recent enrollment/adaptive samples kept in [history].
  /// More history = more stable median, but more storage + more sort cost
  /// on each adaptive update. 10 is a reasonable balance.
  static const int maxHistorySize = 10;

  /// Output dim of the Wespeaker ResNet34-LM speaker embedding.
  static const int embeddingDim = 256;

  /// Aggregate (median across [history]) L2-normalized speaker embedding.
  final Float32List embedding;

  /// Recent embeddings used to compute [embedding]. Initial enrollment
  /// puts the 3 enrollment samples here; adaptive learning appends new
  /// high-confidence matches and trims to [maxHistorySize].
  final List<Float32List> history;

  /// SHA256 of the .tflite the embeddings were produced with.
  final String modelHash;

  /// Wall-clock time of the last save.
  final DateTime updatedAt;

  /// Schema version of this profile.
  final int version;

  const VoiceprintProfile({
    required this.embedding,
    required this.history,
    required this.modelHash,
    required this.updatedAt,
    required this.version,
  });

  /// True if [modelHash] matches the model currently bundled in the app.
  /// Mismatch means the profile was enrolled on a different model and must
  /// be discarded (force re-enrollment).
  bool get isCompatibleWithCurrentModel => modelHash == currentModelHash;

  // ── Serialization ─────────────────────────────────────────────────────
  //
  // Embeddings are encoded as base64 of the raw Float32 byte buffer
  // (zero-copy on the encode side via Float32List.buffer.asUint8List).
  // A 256-dim embedding is 1024 bytes raw, ~1.4 KB base64. A profile with
  // 10 history samples lands around 16 KB total — well within
  // flutter_secure_storage limits.

  static String _encodeEmbedding(Float32List arr) => base64Encode(
        Uint8List.view(arr.buffer, arr.offsetInBytes, arr.lengthInBytes),
      );

  /// Decode using ByteData to avoid alignment assumptions on the
  /// base64-decoded buffer (Uint8List from base64Decode is not guaranteed
  /// to be 4-byte aligned, which Float32List.view requires).
  static Float32List _decodeEmbedding(String s) {
    final bytes = base64Decode(s);
    final result = Float32List(bytes.length ~/ 4);
    final bd = ByteData.sublistView(bytes);
    for (int i = 0; i < result.length; i++) {
      result[i] = bd.getFloat32(i * 4, Endian.little);
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
        'embedding': _encodeEmbedding(embedding),
        'history': history.map(_encodeEmbedding).toList(),
        'modelHash': modelHash,
        'updatedAt': updatedAt.toIso8601String(),
        'version': version,
      };

  factory VoiceprintProfile.fromJson(Map<String, dynamic> json) {
    return VoiceprintProfile(
      embedding: _decodeEmbedding(json['embedding'] as String),
      history: (json['history'] as List<dynamic>)
          .map((e) => _decodeEmbedding(e as String))
          .toList(growable: false),
      modelHash: json['modelHash'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      version: json['version'] as int,
    );
  }
}
