import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/services/voice_detection_service.dart';
import '../../core/storage/secure_storage.dart';
import '../onboarding/voice_activation_step.dart';

/// Standalone wrapper around [VoiceActivationStep] for re-enrolling the
/// user's voice profile from Settings (vs the original onboarding flow).
///
/// Behavior:
///   - On entry: pauses any active voice detection so the recorder used by
///     the step doesn't fight for the mic with the live recognizer.
///   - On exit: resumes detection if it was running before AND voice
///     detection is still enabled in user preferences.
///   - On enrollment success: persists the (possibly updated) activation
///     word and pops with `true` so Settings can refresh its state.
///   - On skip / cancel / back: pops with `false`. The previous voiceprint
///     profile (if any) stays intact because [VoiceprintService.enroll]
///     only writes after a complete successful run.
class VoiceRetrainScreen extends StatefulWidget {
  const VoiceRetrainScreen({super.key});

  @override
  State<VoiceRetrainScreen> createState() => _VoiceRetrainScreenState();
}

class _VoiceRetrainScreenState extends State<VoiceRetrainScreen> {
  // Reference is captured in initState — dispose() can't safely use
  // context (the element may already be unmounted by then).
  late final VoiceDetectionService _detection;
  bool _wasListening = false;

  @override
  void initState() {
    super.initState();
    _detection = context.read<VoiceDetectionService>();
    _wasListening = _detection.isListening;
    if (_wasListening) {
      // Fire-and-forget: stopping is async but we don't need to await
      // before the step starts — recorder open will retry on conflict.
      _detection.stopListening();
    }
  }

  @override
  void dispose() {
    if (_wasListening && _detection.isEnabled) {
      // Resume detection. Profile reload happens via Settings'
      // refreshEnrollmentStatus() call after we pop.
      _detection.startListening();
    }
    super.dispose();
  }

  Future<void> _onComplete(String word) async {
    // VoiceprintService.enroll() already wrote the new profile. Persist
    // the activation word in case the user changed it during retrain.
    try {
      await context.read<SecureStorage>().setActivationWord(word);
      // Keep VoiceDetectionService in sync with the latest stored word
      // so the next startListening() picks it up.
      await context.read<VoiceDetectionService>().updateActivationWord(word);
    } catch (e) {
      debugPrint('[VoiceRetrain] Failed to persist activation word: $e');
    }
    if (!mounted) return;
    context.pop(true);
  }

  void _onSkip() {
    context.pop(false);
  }

  void _onContinue() {
    // Reached after the success state in VoiceActivationStep — same
    // outcome as _onComplete from Settings' perspective.
    context.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Re-train voice'),
      ),
      body: SafeArea(
        child: VoiceActivationStep(
          onContinue: _onContinue,
          onSkip: _onSkip,
          onComplete: _onComplete,
        ),
      ),
    );
  }
}
