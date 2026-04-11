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
    with SingleTickerProviderStateMixin {
  final _wordController = TextEditingController();
  final _recorder = AudioRecorder();
  final List<String> _recordingPaths = [];
  static const _requiredRecordings = 3;

  bool _isRecording = false;
  bool _wordConfirmed = false;
  int _recordingSeconds = 0;
  Timer? _timer;

  @override
  void dispose() {
    _wordController.dispose();
    _recorder.dispose();
    _timer?.cancel();
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

      // On web, record without a file path (uses blob URL)
      // On mobile, record to a temporary file
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

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() => _recordingSeconds++);
        // Auto-stop after 5 seconds
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
    try {
      final path = await _recorder.stop();
      if (path != null && mounted) {
        setState(() {
          _isRecording = false;
          _recordingPaths.add(path);
          _recordingSeconds = 0;
        });

        // All recordings done
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
    // Clear recording paths (files are temporary and will be cleaned up by OS)
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Text(
            'Voice activation',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _wordConfirmed
                ? 'Say your activation word clearly. '
                    'We need $_requiredRecordings recordings to learn your voice.'
                : 'Choose a word or short phrase that will activate '
                    'the emergency alert with your voice.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),

          if (!_wordConfirmed) ...[
            // Step 1: Choose activation word
            TextField(
              controller: _wordController,
              decoration: InputDecoration(
                labelText: 'Activation word',
                hintText: 'e.g. "help me", "socorro", "safe word"',
                prefixIcon: const Icon(Icons.record_voice_over_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _confirmWord(),
            ),
            const SizedBox(height: 12),
            Text(
              'Pick something easy to say but not common in daily '
              'conversation. You can change it later in Settings.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ] else ...[
            // Step 2: Record voice samples
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '"${_wordController.text.trim()}"',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Recording progress
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_requiredRecordings, (index) {
                final isDone = index < _recordingPaths.length;
                final isCurrent = index == _recordingPaths.length;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: isDone
                            ? theme.colorScheme.primary
                            : isCurrent && _isRecording
                                ? theme.colorScheme.error
                                : theme.colorScheme.surfaceContainerHighest,
                        child: isDone
                            ? Icon(Icons.check,
                                color: theme.colorScheme.onPrimary)
                            : isCurrent && _isRecording
                                ? Icon(Icons.mic,
                                    color: theme.colorScheme.onError)
                                : Text(
                                    '${index + 1}',
                                    style: theme.textTheme.bodyLarge,
                                  ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isDone
                            ? 'Done'
                            : isCurrent && _isRecording
                                ? '${_recordingSeconds}s'
                                : '',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              }),
            ),
            const SizedBox(height: 32),

            // Record button
            if (!allDone)
              Center(
                child: GestureDetector(
                  onTap: _isRecording ? _stopRecording : _startRecording,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _isRecording ? 80 : 72,
                    height: _isRecording ? 80 : 72,
                    decoration: BoxDecoration(
                      color: _isRecording
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        if (_isRecording)
                          BoxShadow(
                            color: theme.colorScheme.error.withOpacity(0.4),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                      ],
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      color: _isRecording
                          ? theme.colorScheme.onError
                          : theme.colorScheme.onPrimary,
                      size: 36,
                    ),
                  ),
                ),
              ),

            if (!allDone && !_isRecording)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: Text(
                    'Tap to record ($remaining remaining)',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),

            if (allDone) ...[
              Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle,
                        size: 64, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(
                      'Voice recorded successfully!',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SafeCircle will learn to recognize your voice.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_recordingPaths.isNotEmpty && !_isRecording && !allDone)
              Center(
                child: TextButton(
                  onPressed: _resetRecordings,
                  child: const Text('Start over'),
                ),
              ),
          ],

          const Spacer(),

          // Bottom buttons
          if (!_wordConfirmed) ...[
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: _confirmWord,
                child: const Text('Confirm word'),
              ),
            ),
          ] else if (allDone) ...[
            SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                onPressed: widget.onContinue,
                child: const Text('Continue'),
              ),
            ),
          ],

          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: widget.onSkip,
              child: const Text('Skip for now'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
