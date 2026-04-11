import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:record/record.dart';

/// Onboarding step where the user:
/// 1. Chooses a custom activation word/phrase
/// 2. Records their voice saying it 3 times for calibration
/// 3. The recordings are stored locally for future voice recognition
class VoiceActivationStep extends StatefulWidget {
  final VoidCallback onContinue;
  final VoidCallback onSkip;
  final void Function(String word, List<String> recordingPaths) onComplete;

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

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          bitRate: 128000,
        ),
        path: kIsWeb
            ? ''
            : '/tmp/activation_voice_${_recordingPaths.length + 1}.m4a',
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
          widget.onComplete(_wordController.text.trim(), _recordingPaths);
        }
      }
    } catch (e) {
      debugPrint('[VoiceActivation] Stop error: $e');
      setState(() => _isRecording = false);
    }
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const SizedBox(height: 16),

          // Hero section with gradient icon
          _buildHeroHeader(theme),

          const SizedBox(height: 12),

          Text(
            _wordConfirmed
                ? 'Say your word clearly'
                : 'Set your safe word',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _wordConfirmed
                ? 'We need $_requiredRecordings recordings to learn your unique voice pattern.'
                : 'Choose a word or short phrase that will silently trigger '
                    'an emergency alert just with your voice.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Main content area
          Expanded(
            child: SingleChildScrollView(
              child: !_wordConfirmed
                  ? _buildWordInput(theme)
                  : _buildRecordingUI(theme, remaining, allDone),
            ),
          ),

          // Bottom buttons
          _buildBottomButtons(theme, allDone),
          const SizedBox(height: 16),
        ],
      ),
    );
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
                      'Your voice becomes a silent SOS. If you say this word, '
                      'SafeCircle will send your location and alert your contacts.',
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

        // Recording progress indicators
        Row(
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
        ),
        const SizedBox(height: 32),

        // Big record button with animated rings
        if (!allDone)
          _buildRecordButton(theme)
        else
          _buildSuccessState(theme),

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

        if (_recordingPaths.isNotEmpty && !_isRecording && !allDone)
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
          'Voice recorded!',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'SafeCircle will learn to recognize your unique voice pattern.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
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
        ] else if (allDone) ...[
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: widget.onContinue,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('Continue'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        TextButton(
          onPressed: widget.onSkip,
          child: const Text('Skip for now'),
        ),
      ],
    );
  }
}
