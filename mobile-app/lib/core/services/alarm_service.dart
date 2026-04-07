import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Optional alarm mode — plays a loud siren to attract attention.
///
/// ## Current Status: REQUIRES NATIVE IMPLEMENTATION
///
/// The siren audio playback uses a MethodChannel to native code that
/// must set the audio stream to maximum volume and play a siren sound
/// file in a loop. This native code is NOT yet implemented.
///
/// When native code is missing:
/// - [startAlarm] will set [isActive] to true (so UI can show flash effect)
/// - [nativeAudioAvailable] will be false
/// - No sound will play
///
/// ## What Must Be Built Natively
///
/// Android (Kotlin):
/// - MediaPlayer with AudioManager.STREAM_ALARM at max volume
/// - Play bundled siren.mp3 in loop
/// - MethodChannel handlers for startSiren/stopSiren
///
/// iOS (Swift):
/// - AVAudioPlayer with AVAudioSession.Category.playback
/// - Override silent mode switch
/// - Play bundled siren.mp3 in loop
/// - MethodChannel handlers for startSiren/stopSiren
///
/// ## Safety Constraint
/// NEVER triggers automatically. Only activated by explicit user action.
class AlarmService extends ChangeNotifier {
  static const _channel = MethodChannel('com.safecircle.app/alarm');

  bool _isActive = false;
  bool _nativeAudioAvailable = false;

  bool get isActive => _isActive;

  /// Whether the native siren implementation is available.
  /// False until native Kotlin/Swift code is added.
  bool get nativeAudioAvailable => _nativeAudioAvailable;

  /// Start the alarm siren + screen flash.
  ///
  /// If native code is not implemented:
  /// - [isActive] will be true (UI can show visual flash effect)
  /// - No sound will play
  /// - [nativeAudioAvailable] will be false
  Future<void> startAlarm() async {
    if (_isActive) return;
    _isActive = true;
    notifyListeners();

    try {
      await _channel.invokeMethod('startSiren');
      _nativeAudioAvailable = true;
    } on MissingPluginException {
      // EXPECTED: Native siren code not yet implemented.
      // UI flash effect still works, but no sound.
      debugPrint(
        '[AlarmService] Native siren not available. '
        'Visual alarm active, but no audio. '
        'Implement native MethodChannel handler for production.',
      );
      _nativeAudioAvailable = false;
    }
  }

  /// Stop the alarm.
  Future<void> stopAlarm() async {
    if (!_isActive) return;
    _isActive = false;
    notifyListeners();

    try {
      await _channel.invokeMethod('stopSiren');
    } on MissingPluginException {
      // Expected — native code not yet implemented.
    }
    _nativeAudioAvailable = false;
  }

  @override
  void dispose() {
    stopAlarm();
    super.dispose();
  }
}
