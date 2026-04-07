import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/services/settings_service.dart';
import '../../core/utils/coercion_handler.dart';

/// Screen to set or change the coercion PIN.
/// When entered during an emergency, it shows a fake "cancelled" state
/// while the alert remains active in the background.
class CoercionPinScreen extends StatefulWidget {
  const CoercionPinScreen({super.key});

  @override
  State<CoercionPinScreen> createState() => _CoercionPinScreenState();
}

class _CoercionPinScreenState extends State<CoercionPinScreen> {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _isEnabled = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadPinStatus();
  }

  Future<void> _loadPinStatus() async {
    final coercionHandler = context.read<CoercionHandler>();
    final hasPin = await coercionHandler.hasCoercionPin();
    if (mounted) {
      setState(() => _isEnabled = hasPin);
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final pin = _pinController.text;
    final confirm = _confirmPinController.text;

    if (pin.length < 4) {
      _showError('PIN must be at least 4 digits.');
      return;
    }
    if (pin != confirm) {
      _showError('PINs do not match.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      // Save to local secure storage for offline PIN validation.
      final coercionHandler = context.read<CoercionHandler>();
      await coercionHandler.setCoercionPin(pin);

      // Sync to backend (server stores its own bcrypt hash).
      final settingsService = context.read<SettingsService>();
      await settingsService.setCoercionPin(pin);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Coercion PIN saved.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to save PIN. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _disable() async {
    final coercionHandler = context.read<CoercionHandler>();
    await coercionHandler.clearCoercionPin();
    if (mounted) {
      setState(() => _isEnabled = false);
      _pinController.clear();
      _confirmPinController.clear();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coercion PIN'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: [
          const SizedBox(height: 24),

          // Explanation card
          Card(
            elevation: 0,
            color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: theme.colorScheme.onTertiaryContainer,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'What is a coercion PIN?',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'If someone forces you to cancel an alert, entering this PIN '
                    'will display a fake "cancelled" screen. In reality, the alert '
                    'remains active and your contacts continue to receive updates.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Choose a PIN that is different from your phone unlock code '
                    'and easy for you to remember under stress.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onTertiaryContainer
                          .withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),

          // Enable toggle
          SwitchListTile(
            title: const Text('Enable coercion PIN'),
            value: _isEnabled,
            onChanged: (v) {
              if (!v) {
                _disable();
              } else {
                setState(() => _isEnabled = v);
              }
            },
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),

          // PIN fields (only shown when enabled)
          if (_isEnabled) ...[
            TextFormField(
              controller: _pinController,
              decoration: const InputDecoration(
                labelText: 'Enter PIN',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: _confirmPinController,
              decoration: const InputDecoration(
                labelText: 'Confirm PIN',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 32),

            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text('Save PIN'),
              ),
            ),
          ],

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
