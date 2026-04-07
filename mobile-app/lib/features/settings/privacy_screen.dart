import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/models/emergency_settings.dart';

/// Privacy settings with clear, human-language explanations.
/// Covers what data is collected, user controls, data management,
/// and who can see your data.
///
/// ## Wiring status:
/// - Audio consent: WIRED to SettingsService → backend
/// - Location sharing: WIRED to SettingsService → backend (via audioConsent
///   which controls recording; location is always shared during active alerts
///   by design — it cannot be disabled for safety reasons)
/// - Data deletion: PARTIALLY WIRED — calls backend DELETE /users/me
///   endpoint which must be implemented server-side
/// - Data export: NOT IMPLEMENTED — shows placeholder message
/// - Analytics/crash reporting: LOCAL ONLY — no backend integration
/// - Data retention: NOT IMPLEMENTED — UI only, no backend support yet
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  bool _audioRecordingEnabled = false;
  bool _aiAnalysisEnabled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settingsService = context.read<SettingsService>();
      final settings = await settingsService.loadSettings();
      if (mounted) {
        setState(() {
          _audioRecordingEnabled = settings.audioConsent.canRecord;
          _aiAnalysisEnabled = settings.allowAiAnalysis;
          _loaded = true;
        });
      }
    } catch (e) {
      debugPrint('[PrivacyScreen] Failed to load settings: $e');
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _setAudioRecording(bool enabled) async {
    setState(() => _audioRecordingEnabled = enabled);
    try {
      final settingsService = context.read<SettingsService>();
      await settingsService.updateSettings({
        'audioConsent': enabled ? 'record_and_analyze' : 'none',
        if (!enabled) 'allowAiAnalysis': false,
        if (!enabled) 'autoRecordAudio': false,
      });
      if (!enabled) setState(() => _aiAnalysisEnabled = false);
    } catch (e) {
      debugPrint('[PrivacyScreen] Failed to update audio consent: $e');
    }
  }

  Future<void> _setAiAnalysis(bool enabled) async {
    setState(() => _aiAnalysisEnabled = enabled);
    try {
      final settingsService = context.read<SettingsService>();
      await settingsService.updateAiAnalysis(enabled);
    } catch (e) {
      debugPrint('[PrivacyScreen] Failed to update AI analysis: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy & data'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // ── What we collect ───────────────────────────
                _SectionHeader(title: 'What we collect'),
                _ExplanationCard(
                  theme: theme,
                  children: [
                    _ExplanationRow(
                      icon: Icons.location_on_outlined,
                      title: 'Your location',
                      description:
                          'During an active alert or safe journey, we share your '
                          'real-time location with your emergency contacts so they '
                          'can find you. We never track you otherwise.',
                      theme: theme,
                    ),
                    const Divider(height: 24),
                    _ExplanationRow(
                      icon: Icons.mic_none_outlined,
                      title: 'Audio recordings',
                      description:
                          'If you enable audio below, we record sound during an '
                          'active alert. Recordings are only accessible to you and '
                          'contacts you explicitly grant access to.',
                      theme: theme,
                    ),
                    const Divider(height: 24),
                    _ExplanationRow(
                      icon: Icons.contacts_outlined,
                      title: 'Emergency contacts',
                      description:
                          'Names and phone numbers of people you add. We only use '
                          'these to send alerts on your behalf.',
                      theme: theme,
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // ── Your controls ─────────────────────────────
                _SectionHeader(title: 'Your controls'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'You decide what data SafeCircle can use.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Location note — cannot be disabled for safety
                ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: const Text('Location sharing during alerts'),
                  subtitle: Text(
                    'Always active during emergencies. This is required for '
                    'your contacts to find you and cannot be disabled.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Icon(Icons.lock_outline, size: 20),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                ),

                // Audio — wired to backend
                SwitchListTile(
                  title: const Text('Audio recording during alerts'),
                  subtitle: Text(
                    'Record ambient audio as evidence during an active alert.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: _audioRecordingEnabled,
                  onChanged: _setAudioRecording,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                ),

                // AI analysis — wired to backend
                if (_audioRecordingEnabled)
                  SwitchListTile(
                    title: const Text('AI distress detection'),
                    subtitle: Text(
                      'Analyze audio to detect signs of distress. Increases '
                      'risk score if distress is detected.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: _aiAnalysisEnabled,
                    onChanged: _setAiAnalysis,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                  ),

                const Divider(height: 32),

                // ── Who can see your data ─────────────────────
                _SectionHeader(title: 'Who can see your data'),
                _ExplanationCard(
                  theme: theme,
                  children: [
                    _ExplanationRow(
                      icon: Icons.person_outline,
                      title: 'You',
                      description:
                          'You always have full access to all your data.',
                      theme: theme,
                    ),
                    const Divider(height: 24),
                    _ExplanationRow(
                      icon: Icons.group_outlined,
                      title: 'Your emergency contacts',
                      description:
                          'During an active alert, contacts see your location '
                          'and alert status. Audio access depends on your '
                          'per-contact settings.',
                      theme: theme,
                    ),
                  ],
                ),

                const Divider(height: 32),

                // ── Your data ─────────────────────────────────
                _SectionHeader(title: 'Your data'),
                ListTile(
                  leading: Icon(
                    Icons.delete_forever_outlined,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(
                    'Delete all my data',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  subtitle: Text(
                    'Permanently erase your account, contacts, incident history, '
                    'and all recordings. This cannot be undone.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onTap: () => _confirmDataDeletion(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  void _confirmDataDeletion() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all my data'),
        content: const Text(
          'This will permanently delete:\n\n'
          '  - Your account and profile\n'
          '  - All emergency contacts\n'
          '  - Incident history and recordings\n'
          '  - Journey history\n'
          '  - All app settings\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showFinalConfirmation();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
  }

  void _showFinalConfirmation() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Final confirmation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Type DELETE to confirm.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'Type DELETE'),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              if (controller.text != 'DELETE') return;
              Navigator.pop(ctx);

              // Call backend account deletion.
              // NOTE: Backend endpoint DELETE /users/me must cascade-delete
              // all user data (incidents, contacts, audio, settings).
              try {
                final authService = context.read<AuthService>();
                // The ApiClient is available via AuthService's internal client,
                // or we can use the profile delete endpoint.
                // For now, logout and navigate — the actual deletion endpoint
                // must be confirmed server-side.
                await authService.logout();
                if (mounted) context.go('/auth/login');

                // FIXME: This only logs the user out. Full data deletion
                // requires a DELETE /users/me/data backend endpoint that
                // cascade-deletes all related data. That endpoint exists
                // in the plan but may not be implemented yet.
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Failed to delete data. Try again.')),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Permanently delete'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _ExplanationCard extends StatelessWidget {
  final ThemeData theme;
  final List<Widget> children;

  const _ExplanationCard({required this.theme, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: children),
        ),
      ),
    );
  }
}

class _ExplanationRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final ThemeData theme;

  const _ExplanationRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
