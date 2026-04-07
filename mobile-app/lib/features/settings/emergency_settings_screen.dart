import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/settings_service.dart';

/// Emergency settings: countdown duration, cancel method, trigger configuration.
class EmergencySettingsScreen extends StatefulWidget {
  const EmergencySettingsScreen({super.key});

  @override
  State<EmergencySettingsScreen> createState() =>
      _EmergencySettingsScreenState();
}

class _EmergencySettingsScreenState extends State<EmergencySettingsScreen> {
  double _countdownSeconds = 5;
  String _cancelMethod = 'triple_tap';
  bool _vibrationFeedback = true;
  bool _triggerOnPowerButton = false;
  bool _triggerOnShake = false;
  bool _loaded = false;

  static const _cancelMethods = {
    'triple_tap': 'Triple tap in the corner',
    'swipe_pattern': 'Swipe a specific pattern',
    'pin_code': 'Enter PIN code',
  };

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
          _countdownSeconds = settings.countdownDurationSeconds.toDouble();
          _cancelMethod = settings.normalCancelMethod;
          _loaded = true;
        });
      }
    } catch (e) {
      debugPrint('[EmergencySettings] Failed to load: $e');
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _saveCountdown(double value) async {
    setState(() => _countdownSeconds = value);
    try {
      final settingsService = context.read<SettingsService>();
      await settingsService
          .updateSettings({'countdownDurationSeconds': value.round()});
    } catch (e) {
      debugPrint('[EmergencySettings] Failed to save countdown: $e');
    }
  }

  Future<void> _saveCancelMethod(String method) async {
    setState(() => _cancelMethod = method);
    try {
      final settingsService = context.read<SettingsService>();
      await settingsService.updateSettings({'normalCancelMethod': method});
    } catch (e) {
      debugPrint('[EmergencySettings] Failed to save cancel method: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency settings'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // Countdown duration
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Countdown duration',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Time before the alert is sent to your contacts. '
                    'You can cancel during this period.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _countdownSeconds,
                          min: 3,
                          max: 30,
                          divisions: 27,
                          label: '${_countdownSeconds.round()}s',
                          onChanged: (v) =>
                              setState(() => _countdownSeconds = v),
                          onChangeEnd: _saveCountdown,
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          '${_countdownSeconds.round()}s',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 32),

                // Cancel method
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    'Cancel method',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'How to secretly cancel an alert during the countdown. '
                    'Choose a method that is discreet.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ..._cancelMethods.entries.map((entry) {
                  return RadioListTile<String>(
                    title: Text(entry.value),
                    value: entry.key,
                    groupValue: _cancelMethod,
                    onChanged: (v) {
                      if (v != null) _saveCancelMethod(v);
                    },
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16),
                  );
                }),

                const Divider(height: 32),

                // Feedback
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    'Feedback',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Vibration during countdown'),
                  subtitle: Text(
                    'Subtle vibration pulses to confirm the countdown is active.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: _vibrationFeedback,
                  onChanged: (v) =>
                      setState(() => _vibrationFeedback = v),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                ),

                const Divider(height: 32),

                // Trigger methods
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    'Additional triggers',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Alternative ways to start an alert besides the main button.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                SwitchListTile(
                  title: const Text('Power button (5 presses)'),
                  subtitle: Text(
                    'Press the power button five times rapidly.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: _triggerOnPowerButton,
                  onChanged: (v) =>
                      setState(() => _triggerOnPowerButton = v),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                ),
                SwitchListTile(
                  title: const Text('Shake to alert'),
                  subtitle: Text(
                    'Shake the device vigorously to start an alert.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: _triggerOnShake,
                  onChanged: (v) =>
                      setState(() => _triggerOnShake = v),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }
}
