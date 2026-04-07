import 'package:flutter/material.dart';

/// Represents a single permission the app requests during onboarding.
class PermissionItem {
  final String title;
  final String description;
  final IconData icon;
  final bool isGranted;
  final VoidCallback onRequest;

  const PermissionItem({
    required this.title,
    required this.description,
    required this.icon,
    required this.isGranted,
    required this.onRequest,
  });
}

/// Permission request step displayed during onboarding.
/// Explains why each permission is needed and allows the user to grant them.
class PermissionsStep extends StatelessWidget {
  final List<PermissionItem> permissions;
  final VoidCallback onContinue;

  const PermissionsStep({
    super.key,
    required this.permissions,
    required this.onContinue,
  });

  bool get _allGranted => permissions.every((p) => p.isGranted);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Text(
            'App permissions',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'SafeCircle needs a few permissions to keep you safe. '
            'Each permission is used only when you choose to activate an alert.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: ListView.separated(
              itemCount: permissions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final perm = permissions[index];
                return _PermissionCard(permission: perm);
              },
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: onContinue,
              child: Text(_allGranted ? 'Continue' : 'Continue anyway'),
            ),
          ),
          if (!_allGranted) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                'You can grant permissions later in Settings.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  final PermissionItem permission;

  const _PermissionCard({required this.permission});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: permission.isGranted
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: permission.isGranted
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                permission.icon,
                color: permission.isGranted
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    permission.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    permission.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (permission.isGranted)
              Icon(
                Icons.check_circle,
                color: theme.colorScheme.primary,
                size: 28,
              )
            else
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: permission.onRequest,
                  child: const Text('Allow'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
