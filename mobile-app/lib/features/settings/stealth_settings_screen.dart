import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/services/stealth_mode_service.dart';
import '../../core/utils/coercion_handler.dart';

/// Stealth Mode settings screen.
///
/// Lets the user toggle the disguise (calculator) preference and surfaces
/// the dependency on a Coercion PIN. If stealth is enabled but no PIN is
/// configured, a warning card appears with a direct link to the PIN
/// settings screen.
class StealthSettingsScreen extends StatefulWidget {
  const StealthSettingsScreen({super.key});

  @override
  State<StealthSettingsScreen> createState() => _StealthSettingsScreenState();
}

class _StealthSettingsScreenState extends State<StealthSettingsScreen> {
  bool? _hasPin;

  @override
  void initState() {
    super.initState();
    _checkPin();
  }

  /// Re-check the PIN every time the screen is re-shown (e.g. user just
  /// came back from /settings/coercion-pin after configuring one).
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _checkPin();
  }

  Future<void> _checkPin() async {
    final coercionHandler = context.read<CoercionHandler>();
    final hasPin = await coercionHandler.hasCoercionPin();
    if (mounted) {
      setState(() => _hasPin = hasPin);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stealthService = context.watch<StealthModeService>();
    final preference = stealthService.prefersStealthMode;
    final hasPin = _hasPin ?? false;
    final pinChecked = _hasPin != null;
    final effective = preference && hasPin;

    return Scaffold(
      appBar: AppBar(title: const Text('Stealth Mode')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Status card ──────────────────────────────
          _StatusCard(
            theme: theme,
            preference: preference,
            hasPin: hasPin,
            pinChecked: pinChecked,
            effective: effective,
            onSetPin: () => context.push('/settings/coercion-pin'),
          ),
          const SizedBox(height: 16),

          // ── Toggle ───────────────────────────────────
          Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text('Disguise app as calculator'),
              subtitle: const Text(
                'When you open SafeCircle, it will look like a calculator.',
              ),
              value: preference,
              onChanged: (value) =>
                  stealthService.setPrefersStealthMode(value),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            ),
          ),
          const SizedBox(height: 24),

          // ── Help text ────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'How it works',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'If someone takes your phone and tries to open SafeCircle, '
              'they will see only a calculator. The real app stays hidden '
              'until you type your Coercion PIN followed by =.\n\n'
              'Stealth mode requires a Coercion PIN to work. You can set '
              'or change your PIN in Coercion PIN settings.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final ThemeData theme;
  final bool preference;
  final bool hasPin;
  final bool pinChecked;
  final bool effective;
  final VoidCallback onSetPin;

  const _StatusCard({
    required this.theme,
    required this.preference,
    required this.hasPin,
    required this.pinChecked,
    required this.effective,
    required this.onSetPin,
  });

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color accent;
    final String title;
    final String body;

    if (effective) {
      icon = Icons.shield_outlined;
      accent = theme.colorScheme.primary;
      title = 'Stealth mode is active';
      body = 'When you open SafeCircle, it appears as a calculator. '
          'Type your Coercion PIN followed by = to enter the real app.';
    } else if (preference && pinChecked && !hasPin) {
      icon = Icons.warning_amber_outlined;
      accent = theme.colorScheme.error;
      title = 'Stealth mode is set, but inactive';
      body = 'You enabled stealth, but a Coercion PIN is required to '
          'activate it. Without a PIN, the app will open normally.';
    } else if (!preference) {
      icon = Icons.visibility_off_outlined;
      accent = theme.colorScheme.onSurfaceVariant;
      title = 'Stealth mode is off';
      body = 'The app opens normally on launch. Turn on stealth mode '
          'below to disguise it as a calculator.';
    } else {
      // Preference on, but PIN check still pending.
      icon = Icons.hourglass_empty;
      accent = theme.colorScheme.onSurfaceVariant;
      title = 'Checking status…';
      body = '';
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
                if (preference && pinChecked && !hasPin) ...[
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: onSetPin,
                    icon: const Icon(Icons.pin_outlined, size: 18),
                    label: const Text('Set Coercion PIN'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
