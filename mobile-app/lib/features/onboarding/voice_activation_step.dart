import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../core/services/voiceprint_service.dart';
import '../../core/utils/wav_pcm_reader.dart';

/// Onboarding step where the user:
/// 1. Chooses a custom activation word/phrase.
/// 2. Records their voice saying it 3 times for voiceprint enrollment.
/// 3. SafeCircle's on-device speaker verification model learns their voice
///    so future detections can verify it's really them speaking.
///
/// The 3 PCM samples are deleted from disk immediately after the embedding
/// is computed and saved.
class VoiceActivationStep extends StatefulWidget {
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  /// Called only after enrollment succeeds. Carries just the activation word
  /// — the embedding is already persisted in SecureStorage by VoiceprintService.
  final void Function(String word) onComplete;

  const VoiceActivationStep({
    super.key,
    required this.onContinue,
    required this.onSkip,
    required this.onComplete,
  });

  @override
  State<VoiceActivationStep> createState() => _VoiceActivationStepState();
}

class _VoiceActivationStepState extends State<VoiceActivationStep>
    with TickerProviderStateMixin {
  final _wordController = TextEditingController();
  final _recorder = AudioRecorder();
  final List<String> _recordingPaths = [];
  static const _requiredRecordings = 3;

  bool _isRecording = false;
  bool _wordConfirmed = false;
  bool _isProcessing = false;
  bool _enrollSucceeded = false;
  String? _enrollError;
  int _recordingSeconds = 0;
  Timer? _timer;

  // Animations
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
  }

  @override
  void dispose() {
    _wordController.dispose();
    _recorder.dispose();
    _timer?.cancel();
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  void _confirmWord() {
    final word = _wordController.text.trim();
    if (word.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an activation word.')),
      );
      return;
    }
    if (word.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('The word should have at least 2 characters.')),
      );
      return;
    }
    setState(() => _wordConfirmed = true);
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Microphone permission is required.')),
          );
        }
        return;
      }

      // Save to permanent app directory (not /tmp/ which gets cleaned).
      // Format: 16 kHz mono PCM 16-bit — matches the FBANK pipeline the
      // VoiceprintService.extractEmbedding expects.
      String recordPath = '';
      if (!kIsWeb) {
        final appDir = await getApplicationDocumentsDirectory();
        recordPath =
            '${appDir.path}/activation_voice_${_recordingPaths.length + 1}.pcm';
      }

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: recordPath,
      );

      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });

      _pulseController.repeat(reverse: true);
      _waveController.repeat();

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _recordingSeconds++);
        if (_recordingSeconds >= 5) {
          _stopRecording();
        }
      });
    } catch (e) {
      debugPrint('[VoiceActivation] Recording error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start recording: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    _pulseController.stop();
    _pulseController.reset();
    _waveController.stop();
    _waveController.reset();

    try {
      final path = await _recorder.stop();
      if (path != null && mounted) {
        setState(() {
          _isRecording = false;
          _recordingPaths.add(path);
          _recordingSeconds = 0;
        });

        if (_recordingPaths.length >= _requiredRecordings) {
          _processEnrollment();
        }
      }
    } catch (e) {
      debugPrint('[VoiceActivation] Stop error: $e');
      setState(() => _isRecording = false);
    }
  }

  /// Read the 3 PCM files, run voiceprint enrollment, persist the profile,
  /// and clean up the audio. UX feedback is driven by [_isProcessing],
  /// [_enrollSucceeded], and [_enrollError].
  Future<void> _processEnrollment() async {
    setState(() {
      _isProcessing = true;
      _enrollError = null;
    });

    final voiceprint = context.read<VoiceprintService>();

    if (!voiceprint.isReady) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _enrollError =
            'Voice biometrics unavailable. Please restart the app.';
      });
      return;
    }

    try {
      final samples = <Int16List>[];
      for (final path in _recordingPaths) {
        samples.add(await readPcm16k(File(path)));
      }

      await voiceprint.enroll(samples);

      // Privacy: delete PCM samples immediately. Embedding is what's kept.
      for (final path in _recordingPaths) {
        try {
          await File(path).delete();
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _enrollSucceeded = true;
      });
    } on ArgumentError catch (e) {
      // Bad/empty/short recording — guide user to a quieter spot.
      debugPrint('[VoiceActivation] Enrollment ArgumentError: $e');
      _setEnrollError(
        "We couldn't learn your voice from those recordings. "
        "Try again in a quieter spot?",
      );
    } on StateError catch (e) {
      debugPrint('[VoiceActivation] Enrollment StateError: $e');
      _setEnrollError(
        'Voice biometrics unavailable. Please restart the app.',
      );
    } catch (e, stack) {
      debugPrint('[VoiceActivation] Enrollment failed: $e\n$stack');
      _setEnrollError('Something went wrong. Try again?');
    }
  }

  void _setEnrollError(String msg) {
    if (!mounted) return;
    setState(() {
      _isProcessing = false;
      _enrollError = msg;
    });
  }

  /// Reset to a fresh recording state (called from "Record again" after
  /// an enrollment error). Cleans up any partial PCM files first.
  Future<void> _resetForRetry() async {
    for (final path in _recordingPaths) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _recordingPaths.clear();
      _enrollError = null;
      _enrollSucceeded = false;
      _isProcessing = false;
    });
  }

  void _resetRecordings() {
    setState(() {
      _recordingPaths.clear();
      _wordConfirmed = false;
      _wordController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = _requiredRecordings - _recordingPaths.length;
    final allDone = remaining <= 0;

    return PopScope(
      canPop: !_isProcessing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isProcessing) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please wait — SafeCircle is learning your voice...',
              ),
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 16),
            _buildHeroHeader(theme),
            const SizedBox(height: 12),
            Text(
              _headerTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _headerSubtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                child: !_wordConfirmed
                    ? _buildWordInput(theme)
                    : _buildRecordingUI(theme, remaining, allDone),
              ),
            ),
            _buildBottomButtons(theme, allDone),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String get _headerTitle {
    if (!_wordConfirmed) return 'Set your safe word';
    if (_enrollError != null) return 'Hmm, that didn\'t work';
    if (_enrollSucceeded) return 'Voice learned!';
    if (_isProcessing) return 'Learning your voice...';
    return 'Say your safe word';
  }

  String get _headerSubtitle {
    if (!_wordConfirmed) {
      return 'Choose a word or short phrase that will silently trigger '
          'an emergency alert just with your voice.';
    }
    if (_enrollError != null) return _enrollError!;
    if (_enrollSucceeded) {
      return 'SafeCircle will verify it\'s you before triggering an alert.';
    }
    if (_isProcessing) {
      return 'SafeCircle is creating your voice profile from the 3 recordings.';
    }
    return 'Say your safe word 3 times naturally. SafeCircle will learn '
        'your voice and use it to verify it\'s really you.';
  }

  Widget _buildHeroHeader(ThemeData theme) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.tertiary,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Icon(
        Icons.graphic_eq_rounded,
        size: 40,
        color: theme.colorScheme.onPrimary,
      ),
    );
  }

  Widget _buildWordInput(ThemeData theme) {
    return Column(
      children: [
        // Importance banner
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.shield_outlined,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Why this matters',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Your voice becomes a silent SOS. SafeCircle learns '
                      'your voice so only you can trigger the alert — '
                      'not someone else who happens to say the word.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        TextField(
          controller: _wordController,
          decoration: InputDecoration(
            labelText: 'Activation word',
            hintText: 'e.g. "help me", "socorro", "safe word"',
            prefixIcon: const Icon(Icons.record_voice_over_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerLowest,
          ),
          textCapitalization: TextCapitalization.none,
          textInputAction: TextInputAction.done,
          style: theme.textTheme.titleMedium,
          onSubmitted: (_) => _confirmWord(),
        ),
        const SizedBox(height: 12),

        // Suggestion chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['help me', 'socorro', 'safe word', 'code red'].map((s) {
            return ActionChip(
              label: Text(s),
              avatar: const Icon(Icons.add, size: 16),
              onPressed: () {
                _wordController.text = s;
                _wordController.selection = TextSelection.fromPosition(
                  TextPosition(offset: s.length),
                );
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        Text(
          'Pick something easy to say but not common in daily '
          'conversation. You can change it later in Settings.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildRecordingUI(ThemeData theme, int remaining, bool allDone) {
    return Column(
      children: [
        // Show the chosen word in a highlighted badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primaryContainer,
                theme.colorScheme.tertiaryContainer,
              ],
            ),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.format_quote,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                _wordController.text.trim(),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.format_quote,
                  size: 18, color: theme.colorScheme.primary),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // Progress indicators 1/2/3 (always visible — context for the user)
        _buildIndicators(theme),
        const SizedBox(height: 32),

        // Center widget — depends on state
        if (_isProcessing)
          _buildProcessingState(theme)
        else if (_enrollSucceeded)
          _buildSuccessState(theme)
        else if (_enrollError != null)
          _buildErrorState(theme)
        else if (allDone)
          // Defensive: if all done but no terminal state, kick processing.
          // Should not normally render — _stopRecording triggers
          // _processEnrollment which sets _isProcessing immediately.
          const SizedBox.shrink()
        else
          _buildRecordButton(theme),

        if (!allDone && !_isRecording)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'Tap to record ($remaining remaining)',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

        if (_isRecording)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'Listening... Tap to stop',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

        if (_recordingPaths.isNotEmpty &&
            !_isRecording &&
            !allDone &&
            !_isProcessing)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextButton.icon(
              onPressed: _resetRecordings,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Start over'),
            ),
          ),
      ],
    );
  }

  Widget _buildIndicators(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_requiredRecordings, (index) {
        final isDone = index < _recordingPaths.length;
        final isCurrent = index == _recordingPaths.length;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: isCurrent && _isRecording ? 56 : 48,
                height: isCurrent && _isRecording ? 56 : 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone
                      ? theme.colorScheme.primary
                      : isCurrent && _isRecording
                          ? theme.colorScheme.error
                          : theme.colorScheme.surfaceContainerHighest,
                  boxShadow: [
                    if (isDone)
                      BoxShadow(
                        color: theme.colorScheme.primary
                            .withValues(alpha: 0.3),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    if (isCurrent && _isRecording)
                      BoxShadow(
                        color: theme.colorScheme.error
                            .withValues(alpha: 0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                  ],
                ),
                child: isDone
                    ? Icon(Icons.check_rounded,
                        color: theme.colorScheme.onPrimary, size: 24)
                    : isCurrent && _isRecording
                        ? Icon(Icons.mic,
                            color: theme.colorScheme.onError, size: 24)
                        : Text(
                            '${index + 1}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
              ),
              const SizedBox(height: 6),
              Text(
                isDone
                    ? 'Done'
                    : isCurrent && _isRecording
                        ? '${_recordingSeconds}s'
                        : 'Rec ${index + 1}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isDone
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: isDone ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildRecordButton(ThemeData theme) {
    return GestureDetector(
      onTap: _isRecording ? _stopRecording : _startRecording,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          final scale = _isRecording ? _pulseAnimation.value : 1.0;
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _isRecording
                      ? [
                          theme.colorScheme.error,
                          theme.colorScheme.error.withValues(alpha: 0.8),
                        ]
                      : [
                          theme.colorScheme.primary,
                          theme.colorScheme.tertiary,
                        ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isRecording
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary)
                        .withValues(alpha: 0.4),
                    blurRadius: _isRecording ? 30 : 16,
                    spreadRadius: _isRecording ? 8 : 2,
                  ),
                ],
              ),
              child: Icon(
                _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                color: Colors.white,
                size: 44,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProcessingState(ThemeData theme) {
    return Column(
      children: [
        SizedBox(
          width: 88,
          height: 88,
          child: CircularProgressIndicator(
            strokeWidth: 4,
            valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Building your voice profile',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSuccessState(ThemeData theme) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                theme.colorScheme.primary,
                theme.colorScheme.tertiary,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.3),
                blurRadius: 20,
                spreadRadius: 4,
              ),
            ],
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 48,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Profile saved on this device only',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildErrorState(ThemeData theme) {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.errorContainer,
          ),
          child: Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.tonalIcon(
            onPressed: _resetForRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Record again'),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomButtons(ThemeData theme, bool allDone) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!_wordConfirmed) ...[
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _confirmWord,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Confirm word'),
            ),
          ),
        ] else if (_enrollSucceeded) ...[
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: () => widget.onComplete(_wordController.text.trim()),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Continue'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        // Skip stays available unless we're mid-processing.
        if (!_isProcessing)
          TextButton(
            onPressed: widget.onSkip,
            child: const Text('Skip for now'),
          ),
      ],
    );
  }
}
