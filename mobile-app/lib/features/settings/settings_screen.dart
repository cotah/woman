import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/auth/auth_service.dart';
import '../../core/theme/theme_notifier.dart';

/// Main settings menu with grouped navigation items.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // Safety section
          _SectionHeader(title: 'Safety'),
          _SettingsTile(
            icon: Icons.timer_outlined,
            title: 'Emergency settings',
            subtitle: 'Countdown, cancel method, triggers',
            onTap: () => context.push('/settings/emergency'),
          ),
          _SettingsTile(
            icon: Icons.pin_outlined,
            title: 'Coercion PIN',
            subtitle: 'Set a code that fakes cancellation',
            onTap: () => context.push('/settings/coercion-pin'),
          ),
          _SettingsTile(
            icon: Icons.mic_outlined,
            title: 'Audio & recording',
            subtitle: 'Consent, AI analysis, sharing',
            onTap: () => context.push('/settings/audio'),
          ),
          _SettingsTile(
            icon: Icons.record_voice_over_outlined,
            title: 'Voice detection',
            subtitle: 'Activation word, continuous listening',
            onTap: () => context.push('/settings/voice'),
          ),
          _SettingsTile(
            icon: Icons.radar_outlined,
            title: 'Geofence zones',
            subtitle: 'Safe zones, watch zones, auto-alerts',
            onTap: () => context.push('/settings/geofence'),
          ),

          const SizedBox(height: 8),

          // Appearance section
          _SectionHeader(title: 'Appearance'),
          _ThemeModeTile(),

          const SizedBox(height: 8),

          // Account section
          _SectionHeader(title: 'Account'),
          _SettingsTile(
            icon: Icons.people_outline,
            title: 'Trusted contacts',
            subtitle: 'Manage your safety network',
            onTap: () => context.push('/contacts'),
          ),
          _SettingsTile(
            icon: Icons.shield_outlined,
            title: 'Privacy & data',
            subtitle: 'Data retention, account deletion',
            onTap: () => context.push('/settings/privacy'),
          ),

          const SizedBox(height: 8),

          // Info section
          _SectionHeader(title: 'Information'),
          _SettingsTile(
            icon: Icons.help_outline,
            title: 'Help & FAQ',
            subtitle: 'How it works, common questions',
            onTap: () => context.push('/help'),
          ),
          _SettingsTile(
            icon: Icons.description_outlined,
            title: 'Legal disclaimers',
            subtitle: 'Terms, limitations, responsibilities',
            onTap: () => context.push('/disclaimer'),
          ),
          _SettingsTile(
            icon: Icons.science_outlined,
            title: 'Test mode',
            subtitle: 'Try the alert flow without real notifications',
            onTap: () => context.push('/test-mode'),
          ),
          _SettingsTile(
            icon: Icons.monitor_heart_outlined,
            title: 'System readiness',
            subtitle: 'Permissions, connectivity, provider status',
            onTap: () => context.push('/diagnostics'),
          ),

          const SizedBox(height: 24),

          // Sign out
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton(
              onPressed: () {
                _confirmSignOut(context);
              },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
              ),
              child: const Text('Sign out'),
            ),
          ),
          const SizedBox(height: 16),

          // App version
          Center(
            child: Text(
              'SafeCircle v1.0.0',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final authService = context.read<AuthService>();
              await authService.logout();
              // Router redirect handles navigation on auth state change.
            },
            child: const Text('Sign out'),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      minVerticalPadding: 12,
    );
  }
}

class _ThemeModeTile extends StatelessWidget {
  const _ThemeModeTile();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeNotifier = context.watch<ThemeNotifier>();

    String label;
    IconData icon;
    switch (themeNotifier.themeMode) {
      case ThemeMode.light:
        label = 'Light';
        icon = Icons.light_mode;
        break;
      case ThemeMode.dark:
        label = 'Dark';
        icon = Icons.dark_mode;
        break;
      case ThemeMode.system:
        label = 'System';
        icon = Icons.settings_brightness;
        break;
    }

    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
      title: const Text('Theme'),
      subtitle: Text(
        label,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode, size: 18),
          ),
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.settings_brightness, size: 18),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode, size: 18),
          ),
        ],
        selected: {themeNotifier.themeMode},
        onSelectionChanged: (selected) {
          themeNotifier.setThemeMode(selected.first);
        },
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      minVerticalPadding: 12,
    );
  }
}
