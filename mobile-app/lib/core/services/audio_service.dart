import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/emergency_settings.dart';

/// Audio recording service using the `record` package.
/// Chunks recordings into segments and uploads them to the backend.
class AudioService extends ChangeNotifier {
  final ApiClient _apiClient;
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  String? _activeIncidentId;
  AudioConsentLevel _consentLevel = AudioConsentLevel.none;
  Timer? _chunkTimer;
  int _chunkIndex = 0;
  String? _currentFilePath;

  /// Duration of each audio chunk in seconds.
  static const int chunkDurationSeconds = 30;

  AudioService({required ApiClient apiClient}) : _apiClient = apiClient;

  bool get isRecording => _isRecording;
  int get chunkIndex => _chunkIndex;

  /// Update consent level (call when emergency settings are loaded).
  void updateConsentLevel(AudioConsentLevel level) {
    _consentLevel = level;
  }

  /// Start recording audio for an incident.
  /// Respects the user's consent settings - will not record if consent is [none].
  Future<bool> startRecording({required String incidentId}) async {
    if (_isRecording) return true;
    if (!_consentLevel.canRecord) {
      debugPrint(
          '[AudioService] Recording denied: consent level is ${_consentLevel.apiValue}');
      return false;
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      debugPrint('[AudioService] Microphone permission denied');
      return false;
    }

    _activeIncidentId = incidentId;
    _chunkIndex = 0;

    await _startNewChunk();

    // Set up timer for automatic chunk rotation.
    _chunkTimer = Timer.periodic(
      const Duration(seconds: chunkDurationSeconds),
      (_) => _rotateChunk(),
    );

    _isRecording = true;
    notifyListeners();
    return true;
  }

  /// Stop recording and upload the final chunk.
  Future<void> stopRecording() async {
    _chunkTimer?.cancel();
    _chunkTimer = null;

    if (_isRecording) {
      await _finalizeCurrentChunk();
    }

    _isRecording = false;
    _activeIncidentId = null;
    notifyListeners();
  }

  /// Rotate: finalize current chunk and start a new one.
  Future<void> _rotateChunk() async {
    await _finalizeCurrentChunk();
    await _startNewChunk();
  }

  Future<void> _startNewChunk() async {
    final dir = await getTemporaryDirectory();
    _currentFilePath =
        '${dir.path}/safecircle_audio_${_activeIncidentId}_$_chunkIndex.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: _currentFilePath!,
    );
  }

  Future<void> _finalizeCurrentChunk() async {
    final path = await _recorder.stop();
    if (path == null || _activeIncidentId == null) return;

    final file = File(path);
    if (!await file.exists()) return;

    final fileSize = await file.length();
    if (fileSize == 0) {
      await file.delete();
      return;
    }

    // Upload in background - don't block the recording flow.
    _uploadChunk(file, _chunkIndex);
    _chunkIndex++;
  }

  Future<void> _uploadChunk(File file, int index) async {
    if (_activeIncidentId == null) return;

    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: 'chunk_$index.m4a',
          contentType: DioMediaType('audio', 'mp4'),
        ),
      });

      await _apiClient.upload(
        ApiEndpoints.uploadAudio(_activeIncidentId!),
        data: formData,
        queryParameters: {
          'duration': chunkDurationSeconds.toString(),
        },
      );

      debugPrint(
          '[AudioService] Uploaded chunk $index for incident $_activeIncidentId');
    } catch (e) {
      debugPrint('[AudioService] Failed to upload chunk $index: $e');
      // Keep the file for retry - don't delete on failure.
      return;
    }

    // Clean up local file after successful upload.
    try {
      await file.delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    _chunkTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}
