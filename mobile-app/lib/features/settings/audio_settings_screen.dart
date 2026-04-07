import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/emergency_settings.dart';
import '../../core/services/settings_service.dart';

/// Audio settings: consent, AI analysis, sharing preferences.
class AudioSettingsScreen extends StatefulWidget {
  const AudioSettingsScreen({super.key});

  @override
  State<AudioSettingsScreen> createState() => _AudioSettingsScreenState();
}

class _AudioSettingsScreenState extends State<AudioSettingsScreen> {
  bool _audioRecordingEnabled = false;
  bool _aiAnalysisEnabled = false;
  bool _shareWithContacts = false;
  bool _autoRecord = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settingsService = context.read<SettingsService>();
    try {
      final settings = await settingsService.loadSettings();
      if (mounted) {
        setState(() {
          _audioRecordingEnabled = settings.audioConsent.canRecord;
          _aiAnalysisEnabled = settings.allowAiAnalysis;
          _shareWithContacts = settings.shareAudioWithContacts;
          _autoRecord = settings.autoRecordAudio;
          _loaded = true;
        });
      }
    } catch (e) {
      debugPrint('[AudioSettings] Failed to load: $e');
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _setAudioRecording(bool enabled) async {
    final settingsService = context.read<SettingsService>();
    final consent = enabled ? 'record_and_analyze' : 'none';

    setState(() {
      _audioRecordingEnabled = enabled;
      if (!enabled) {
        _aiAnalysisEnabled = false;
        _shareWithContacts = false;
        _autoRecord = false;
      }
    });

    try {
      await settingsService.updateSettings({
        'audioConsent': consent,
        if (!enabled) 'allowAiAnalysis': false,
        if (!enabled) 'shareAudioWithContacts': false,
        if (!enabled) 'autoRecordAudio': false,
      });
    } catch (e) {
      debugPrint('[AudioSettings] Failed to update: $e');
    }
  }

  Future<void> _setAiAnalysis(bool enabled) async {
    setState(() => _aiAnalysisEnabled = enabled);
    try {
      final settingsService = context.read<SettingsService>();
      await settingsService.updateAiAnalysis(enabled);
    } catch (e) {
      debugPrint('[AudioSettings] Failed to update AI: $e');
    }
  }

  Future<void> _setSharing(bool enabled) async {
    setState(() => _shareWithContacts = enabled);
    try {
      final settingsService = context.read<SettingsService>();
      await settingsService.updateAudioSharing(enabled);
    } catch (e) {
      debugPrint('[AudioSettings] Failed to update sharing: $e');
    }
  }

  Future<void> _setAutoRecord(bool enabled) async {
    setState(() => _autoRecord = enabled);
    try {
      final settingsService = context.read<SettingsService>();
      await settingsService.updateAutoRecord(enabled);
    } catch (e) {
      debugPrint('[AudioSettings] Failed to update auto-record: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audio & recording')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio & recording'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // Consent section
          _SectionHeader(title: 'Recording consent'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              elevation: 0,
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.gavel_outlined,
                      size: 20,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Audio recording laws vary by jurisdiction. You are responsible for '
                        'complying with local laws regarding consent to record conversations.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          SwitchListTile(
            title: const Text('Enable audio recording'),
            subtitle: Text(
              'Record audio from your microphone during an active alert.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            value: _audioRecordingEnabled,
            onChanged: (v) {
              if (v) {
                _showConsentDialog();
              } else {
                _setAudioRecording(false);
              }
            },
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),

          if (_audioRecordingEnabled) ...[
            const Divider(height: 32),

            SwitchListTile(
              title: const Text('Auto-record on activation'),
              subtitle: Text(
                'Start recording automatically when an alert activates.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              value: _autoRecord,
              onChanged: _setAutoRecord,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),

            const Divider(height: 32),

            // AI analysis
            _SectionHeader(title: 'AI analysis'),
            SwitchListTile(
              title: const Text('Enable AI audio analysis'),
              subtitle: Text(
                'Automatically analyze audio for distress detection. '
                'Audio is processed securely.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              value: _aiAnalysisEnabled,
              onChanged: _setAiAnalysis,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),

            const Divider(height: 32),

            // Sharing
            _SectionHeader(title: 'Sharing preferences'),
            SwitchListTile(
              title: const Text('Share with trusted contacts'),
              subtitle: Text(
                'Contacts with audio permission can access recordings.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              value: _shareWithContacts,
              onChanged: _setSharing,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showConsentDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Audio recording consent'),
        content: const Text(
          'By enabling audio recording, you confirm that:\n\n'
          '1. You understand and accept the legal implications.\n\n'
          '2. You will comply with local recording laws.\n\n'
          '3. Recordings are stored securely and can be deleted at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _setAudioRecording(true);
            },
            child: const Text('I understand'),
          ),
        ],
      ),
    );
  }
}

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
