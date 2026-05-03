import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/models/voiceprint_profile.dart';
import '../../core/services/voice_detection_service.dart';
import '../../core/services/voiceprint_service.dart';
import '../../core/storage/secure_storage.dart';

/// Voice detection settings screen.
///
/// Allows the user to:
/// - Enable/disable continuous voice listening
/// - View/change the activation word
/// - See real-time status of the voice engine
/// - Test the detection live
class VoiceSettingsScreen extends StatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  State<VoiceSettingsScreen> createState() => _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends State<VoiceSettingsScreen> {
  final _wordController = TextEditingController();
  bool _isSaving = false;

  /// Future holding the currently-saved voiceprint profile (or null if
  /// none is enrolled). Stored in state so the FutureBuilder doesn't
  /// rebuild a new request on every frame; refreshed explicitly via
  /// [_refreshProfileFuture] when something changes (after retrain,
  /// after enroll, etc).
  Future<VoiceprintProfile?>? _profileFuture;

  @override
  void initState() {
    super.initState();
    final voiceService = context.read<VoiceDetectionService>();
    _wordController.text = voiceService.activationWord;
    _profileFuture = context.read<VoiceprintService>().loadProfile();
  }

  void _refreshProfileFuture() {
    setState(() {
      _profileFuture = context.read<VoiceprintService>().loadProfile();
    });
  }

  Future<void> _openRetrain() async {
    final didRetrain =
        await context.push<bool>('/settings/voice/retrain');
    if (!mounted) return;
    if (didRetrain == true) {
      // Refresh both: VoiceDetectionService.requiresEnrollment may have
      // flipped, and the profile we just enrolled needs to surface in
      // the card.
      await context.read<VoiceDetectionService>().refreshEnrollmentStatus();
      if (!mounted) return;
      _refreshProfileFuture();
    }
  }

  @override
  void dispose() {
    _wordController.dispose();
    super.dispose();
  }

  Future<void> _saveActivationWord() async {
    final word = _wordController.text.trim();
    if (word.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      final voiceService = context.read<VoiceDetectionService>();
      await voiceService.updateActivationWord(word);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Activation word updated to "$word"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final voiceService = context.watch<VoiceDetectionService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Detection'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Status Card ──
          _buildStatusCard(theme, voiceService),
          const SizedBox(height: 24),

          // ── Enable/Disable Toggle ──
          _buildToggleSection(theme, voiceService),
          const SizedBox(height: 24),

          // ── Activation Word ──
          _buildActivationWordSection(theme, voiceService),
          const SizedBox(height: 24),

          // ── Voice Biometrics (profile status + retrain) ──
          _buildVoiceprintCard(theme, voiceService),
          const SizedBox(height: 24),

          // ── Live Detection Monitor ──
          if (voiceService.isListening) ...[
            _buildLiveMonitor(theme, voiceService),
            const SizedBox(height: 24),
          ],

          // ── How It Works ──
          _buildInfoSection(theme),
          const SizedBox(height: 16),

          // ── Debug (collapsible, default closed) ──
          _buildDebugTile(theme),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme, VoiceDetectionService service) {
    final isActive = service.isEnabled && service.isListening;
    final color = isActive ? Colors.green : Colors.grey;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isActive
              ? [Colors.green.shade700, Colors.green.shade500]
              : [Colors.grey.shade600, Colors.grey.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isActive ? Icons.mic : Icons.mic_off,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive ? 'Listening...' : 'Voice Detection Off',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isActive
                      ? 'Say "${service.activationWord}" to trigger SOS'
                      : service.isInitialized
                          ? 'Enable to start listening for your activation word'
                          : 'Set an activation word first',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
          if (isActive)
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.greenAccent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.greenAccent.withValues(alpha: 0.6),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToggleSection(ThemeData theme, VoiceDetectionService service) {
    return Card(
      child: SwitchListTile(
        title: const Text('Enable Voice Detection'),
        subtitle: Text(
          service.isEnabled
              ? 'Continuously listening for activation word'
              : 'Tap to enable background voice listening',
          style: theme.textTheme.bodySmall,
        ),
        secondary: Icon(
          service.isEnabled ? Icons.hearing : Icons.hearing_disabled,
          color: service.isEnabled
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        value: service.isEnabled,
        onChanged: service.activationWord.isEmpty
            ? null
            : (enabled) async {
                if (enabled) {
                  await service.enable();
                } else {
                  await service.disable();
                }
              },
      ),
    );
  }

  Widget _buildActivationWordSection(
      ThemeData theme, VoiceDetectionService service) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.record_voice_over,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Activation Word',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'This is the word or phrase you say out loud to trigger an emergency SOS. '
              'Choose something you can say naturally but wouldn\'t say by accident.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _wordController,
                    decoration: InputDecoration(
                      hintText: 'e.g., "help me now"',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      suffixIcon: _wordController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _wordController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _saveActivationWord(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _isSaving ||
                          _wordController.text.trim().isEmpty ||
                          _wordController.text.trim().toLowerCase() ==
                              service.activationWord
                      ? null
                      : _saveActivationWord,
                  child: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
            if (service.activationWord.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Current: "${service.activationWord}"',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLiveMonitor(ThemeData theme, VoiceDetectionService service) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Live Monitor',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Last recognized text
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Last heard:',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    service.lastRecognized.isEmpty
                        ? '(waiting for speech...)'
                        : '"${service.lastRecognized}"',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: service.lastRecognized.isEmpty
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Confidence bar
            if (service.confidence > 0) ...[
              Row(
                children: [
                  Text(
                    'Match confidence:',
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: service.confidence,
                      backgroundColor: theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(
                        service.confidence >= 0.7
                            ? Colors.green
                            : service.confidence >= 0.5
                                ? Colors.orange
                                : Colors.red,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(service.confidence * 100).toStringAsFixed(0)}%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoSection(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'How it works',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoItem(
              icon: Icons.hearing,
              text:
                  'Listens continuously using your device\'s speech engine',
            ),
            _InfoItem(
              icon: Icons.compare_arrows,
              text:
                  'Compares what you say against your activation word using fuzzy matching',
            ),
            _InfoItem(
              icon: Icons.warning_amber,
              text:
                  'When a 70%+ match is detected, an emergency SOS is triggered automatically',
            ),
            _InfoItem(
              icon: Icons.lock,
              text:
                  'All processing happens on your device — no audio is sent to any server',
            ),
            _InfoItem(
              icon: Icons.battery_saver,
              text:
                  'Optimized for low battery usage with short listening sessions',
            ),
          ],
        ),
      ),
    );
  }

  // ── Voice biometrics card ──────────────────────────────────────────

  Widget _buildVoiceprintCard(
    ThemeData theme,
    VoiceDetectionService detection,
  ) {
    return FutureBuilder<VoiceprintProfile?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Card(
            child: SizedBox(
              height: 88,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation(theme.colorScheme.primary),
                ),
              ),
            ),
          );
        }

        final profile = snapshot.data;
        if (profile != null) {
          return _buildVoiceprintActiveCard(theme, profile);
        }

        // No profile. Differentiate "needs setup after migration" vs
        // "never set up" — the migration banner is more urgent.
        if (detection.requiresEnrollment) {
          return _buildVoiceprintMigrationCard(theme);
        }
        return _buildVoiceprintNotSetUpCard(theme);
      },
    );
  }

  /// State 1: profile null + requiresEnrollment=false. Never enrolled
  /// (or skipped during onboarding). Friendly call-to-action.
  Widget _buildVoiceprintNotSetUpCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined,
                    color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Voice biometrics',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Not set up.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Voice activation only triggers when it\'s really you '
              'saying the word.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openRetrain,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Set up voice biometrics'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// State 2: profile null + requiresEnrollment=true. Migration from a
  /// pre-voiceprint install. Amber tint to signal "important, act now".
  Widget _buildVoiceprintMigrationCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.45),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.tertiary.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: theme.colorScheme.tertiary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Voice activation needs setup',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'You have an activation word saved but no voice profile '
              'yet. Set up voice biometrics so only YOU can trigger the '
              'alert.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _openRetrain,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Set up now'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// State 3: profile present. Quiet "all good" tone, retrain demoted
  /// to a tonal button so users don't accidentally invalidate a working
  /// profile.
  Widget _buildVoiceprintActiveCard(
    ThemeData theme,
    VoiceprintProfile profile,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.verified_user_rounded,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'Voice profile active',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildKeyValueRow(
              theme,
              label: 'Last updated',
              value: _relativeDuration(profile.updatedAt),
            ),
            const SizedBox(height: 4),
            _buildKeyValueRow(
              theme,
              label: 'Trained on',
              value:
                  '${profile.history.length}/${VoiceprintProfile.maxHistorySize} samples',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _openRetrain,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Re-train voice profile'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyValueRow(
    ThemeData theme, {
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ── Debug expansion tile ───────────────────────────────────────────

  Widget _buildDebugTile(ThemeData theme) {
    final voiceprint = context.watch<VoiceprintService>();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: const Icon(Icons.bug_report_outlined),
        title: const Text('Voice profile (debug)'),
        subtitle: Text(
          'Engine: ${_statusLabel(voiceprint.status)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _buildDebugRow(theme, 'Engine status', _statusLabel(voiceprint.status)),
          _buildDebugRow(
            theme,
            'Model load',
            voiceprint.loadDuration != null
                ? '${voiceprint.loadDuration!.inMilliseconds} ms'
                : '—',
          ),
          _buildDebugRow(
            theme,
            'Warmup',
            voiceprint.warmupDuration != null
                ? '${voiceprint.warmupDuration!.inMilliseconds} ms'
                : '—',
          ),
          FutureBuilder<VoiceprintProfile?>(
            future: _profileFuture,
            builder: (context, snapshot) {
              final profile = snapshot.data;
              if (profile == null) {
                return _buildDebugRow(theme, 'Profile', 'not enrolled');
              }
              final ageDays =
                  DateTime.now().difference(profile.updatedAt).inDays;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDebugRow(theme, 'Profile age', '$ageDays day(s)'),
                  _buildDebugRow(
                    theme,
                    'Samples',
                    '${profile.history.length}/${VoiceprintProfile.maxHistorySize}',
                  ),
                  _buildDebugRow(
                    theme,
                    'Model hash',
                    '${profile.modelHash.substring(0, 12)}…',
                  ),
                ],
              );
            },
          ),
          if (voiceprint.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Error: ${voiceprint.errorMessage}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _statusLabel(VoiceprintStatus s) {
    switch (s) {
      case VoiceprintStatus.uninitialized:
        return 'uninitialized';
      case VoiceprintStatus.loading:
        return 'loading';
      case VoiceprintStatus.ready:
        return 'ready';
      case VoiceprintStatus.error:
        return 'error';
    }
  }

  Widget _buildDebugRow(ThemeData theme, String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              key,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Human-friendly duration formatter:
  ///   - < 1 minute       → "just now"
  ///   - < 1 hour         → "X min ago"
  ///   - < 1 day          → "X hour(s) ago"
  ///   - < 30 days        → "X day(s) ago"
  ///   - >= 30 days       → "MMM D, YYYY" (e.g. "Apr 30, 2026")
  String _relativeDuration(DateTime when) {
    final now = DateTime.now();
    final diff = now.difference(when);
    if (diff.inDays >= 30) {
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[when.month - 1]} ${when.day}, ${when.year}';
    }
    if (diff.inDays >= 1) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    }
    if (diff.inHours >= 1) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    if (diff.inMinutes >= 1) {
      return '${diff.inMinutes} min ago';
    }
    return 'just now';
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
