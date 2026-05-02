import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';

import '../../core/auth/auth_service.dart';
import '../../core/services/background_service.dart';
import '../../core/services/contacts_service.dart';
import '../../core/services/location_tracker_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/stealth_mode_service.dart';
import '../../core/storage/secure_storage.dart';
import 'permissions_step.dart';
import 'voice_activation_step.dart';

/// Multi-step onboarding flow:
/// 0 - Welcome
/// 1 - Permissions (location, notifications, microphone)
/// 2 - Stealth mode opt-in (disguise app as calculator)
/// 3 - Voice activation setup (custom word + voice recording)
/// 4 - Add first trusted contact
/// 5 - Set emergency message
/// 6 - Completion
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
  final _pageController = PageController();
  int _currentStep = 0;
  static const _totalSteps = 7;

  // Permission state
  bool _locationGranted = false;
  bool _notificationsGranted = false;
  bool _microphoneGranted = false;

  // Stealth mode opt-in (defaults to true — protective default)
  bool _stealthModeEnabled = true;

  // Contact form
  final _contactNameController = TextEditingController();
  String _contactPhone = '';
  bool _isSavingContact = false;

  // Voice activation. Enrollment (PCM samples → embedding → SecureStorage)
  // happens inside VoiceActivationStep itself; only the activation word
  // needs to bubble up to be persisted alongside the other onboarding state.
  String _activationWord = '';

  // Emergency message
  final _emergencyMessageController = TextEditingController(
    text: 'I may be in danger. Please check on me or contact emergency services.',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkExistingPermissions();
  }

  /// Re-check permissions when user returns from iOS Settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkExistingPermissions();
    }
  }

  Future<void> _checkExistingPermissions() async {
    final locPerm = await Geolocator.checkPermission();
    final micPerm = await Permission.microphone.status;
    final notifPerm = await Permission.notification.status;

    debugPrint('[Onboarding] Permissions check: '
        'location=${locPerm.name}, '
        'mic=${micPerm.name}, '
        'notif=${notifPerm.name}');

    if (mounted) {
      setState(() {
        _locationGranted = locPerm == LocationPermission.always ||
            locPerm == LocationPermission.whileInUse;
        _microphoneGranted = micPerm.isGranted;
        _notificationsGranted = notifPerm.isGranted;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _contactNameController.dispose();
    _emergencyMessageController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep++);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.animateToPage(
        _currentStep,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _requestLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable location services on your device.'),
          ),
        );
      }
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    debugPrint('[Onboarding] Location permission result: ${permission.name}');

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permission permanently denied. '
              'Please enable it in your device Settings.',
            ),
          ),
        );
      }
      await openAppSettings();
    }

    // Always re-check all permissions to sync UI with actual state
    await _checkExistingPermissions();
  }

  Future<void> _requestNotifications() async {
    final status = await Permission.notification.request();
    debugPrint('[Onboarding] Notification permission result: ${status.name}');

    if (status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notification permission denied. '
              'Enable it in Settings to receive alerts.',
            ),
          ),
        );
      }
      await openAppSettings();
    }

    // Always re-check all permissions to sync UI with actual state
    await _checkExistingPermissions();
  }

  Future<void> _requestMicrophone() async {
    final status = await Permission.microphone.request();
    debugPrint('[Onboarding] Microphone permission result: ${status.name}');

    if (status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Microphone permission denied. '
              'Enable it in Settings to use audio recording.',
            ),
          ),
        );
      }
      await openAppSettings();
    }

    // Always re-check all permissions to sync UI with actual state
    await _checkExistingPermissions();
  }

  Future<void> _saveContact() async {
    final name = _contactNameController.text.trim();
    final phone = _contactPhone.trim();

    if (name.isEmpty || phone.isEmpty) {
      _nextStep(); // Skip if empty
      return;
    }

    setState(() => _isSavingContact = true);
    try {
      final contactsService = context.read<ContactsService>();
      await contactsService.addContact(
        name: name,
        phone: phone,
        priority: 1,
      );
      if (mounted) _nextStep();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save contact: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingContact = false);
    }
  }

  Future<void> _saveEmergencyMessage() async {
    final message = _emergencyMessageController.text.trim();
    if (message.isNotEmpty) {
      try {
        final settingsService = context.read<SettingsService>();
        await settingsService.updateSettings({'emergencyMessage': message});
      } catch (e) {
        debugPrint('[Onboarding] Failed to save emergency message: $e');
      }
    }
    _nextStep();
  }

  Future<void> _completeOnboarding() async {
    try {
      final storage = context.read<SecureStorage>();
      final authService = context.read<AuthService>();
      final userId = authService.state.user?.id;
      await storage.setOnboardingComplete(userId: userId);
      if (_activationWord.isNotEmpty) {
        await storage.setActivationWord(_activationWord);
      }

      // Persist stealth mode preference. Effective stealth still requires
      // a Coercion PIN (handled at runtime by StealthModeService); the
      // user is prompted to set one later in Settings if needed.
      try {
        final stealthService = context.read<StealthModeService>();
        await stealthService.setPrefersStealthMode(_stealthModeEnabled);
      } catch (e) {
        debugPrint('[Onboarding] Failed to save stealth preference: $e');
      }

      // Start always-on background service — the user authorized this
      // by completing onboarding (consent is given in the completion step)
      final backgroundService = context.read<BackgroundService>();
      await backgroundService.startAlwaysOnMode();
      await backgroundService.requestBatteryOptimizationExemption();

      // Start 24/7 location tracking
      final locationTracker = context.read<LocationTrackerService>();
      await locationTracker.startTracking();
    } catch (e) {
      debugPrint('[Onboarding] Failed to save completion flag: $e');
    }
    if (mounted) context.go('/home');
  }

  void _onVoiceComplete(String word) {
    // Voice biometrics enrollment already happened inside VoiceActivationStep
    // (samples were processed by VoiceprintService.enroll and the resulting
    // profile saved to SecureStorage). We only need the word here.
    _activationWord = word;
    _nextStep();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Progress indicator
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  if (_currentStep > 0)
                    IconButton(
                      onPressed: _previousStep,
                      icon: const Icon(Icons.arrow_back),
                      iconSize: 24,
                      padding: const EdgeInsets.all(12),
                    )
                  else
                    const SizedBox(width: 48),
                  Expanded(
                    child: _StepIndicator(
                      totalSteps: _totalSteps,
                      currentStep: _currentStep,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _WelcomeStep(onContinue: _nextStep),
                  PermissionsStep(
                    permissions: [
                      PermissionItem(
                        title: 'Location',
                        description:
                            'Share your real-time location with trusted contacts '
                            'during an alert so they can find you.',
                        icon: Icons.location_on_outlined,
                        isGranted: _locationGranted,
                        onRequest: _requestLocation,
                      ),
                      PermissionItem(
                        title: 'Notifications',
                        description:
                            'Receive alerts when a contact needs help or '
                            'when important status changes occur.',
                        icon: Icons.notifications_outlined,
                        isGranted: _notificationsGranted,
                        onRequest: _requestNotifications,
                      ),
                      PermissionItem(
                        title: 'Microphone',
                        description:
                            'Record audio during an emergency for evidence. '
                            'You control when this is enabled.',
                        icon: Icons.mic_outlined,
                        isGranted: _microphoneGranted,
                        onRequest: _requestMicrophone,
                      ),
                    ],
                    onContinue: _nextStep,
                  ),
                  _StealthModeStep(
                    onChanged: (value) =>
                        setState(() => _stealthModeEnabled = value),
                    onContinue: _nextStep,
                  ),
                  VoiceActivationStep(
                    onContinue: _nextStep,
                    onSkip: _nextStep,
                    onComplete: _onVoiceComplete,
                  ),
                  _AddContactStep(
                    nameController: _contactNameController,
                    isSaving: _isSavingContact,
                    onPhoneChanged: (phone) => _contactPhone = phone,
                    onContinue: _saveContact,
                    onSkip: _nextStep,
                  ),
                  _EmergencyMessageStep(
                    messageController: _emergencyMessageController,
                    onContinue: _saveEmergencyMessage,
                  ),
                  _CompletionStep(onComplete: _completeOnboarding),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Step indicator
// ─────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int totalSteps;
  final int currentStep;

  const _StepIndicator({required this.totalSteps, required this.currentStep});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSteps, (index) {
        final isActive = index <= currentStep;
        return Expanded(
          child: Container(
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Step 0: Welcome
// ─────────────────────────────────────────────────────────

class _WelcomeStep extends StatelessWidget {
  final VoidCallback onContinue;
  const _WelcomeStep({required this.onContinue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(flex: 2),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.shield_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Welcome to SafeCircle',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'A personal safety tool that connects you with people you trust. '
            'Set up your safety network in a few steps.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(flex: 3),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: onContinue,
              child: const Text('Get started'),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Step 2: Stealth mode opt-in
// ─────────────────────────────────────────────────────────

class _StealthModeStep extends StatelessWidget {
  final ValueChanged<bool> onChanged;
  final VoidCallback onContinue;

  const _StealthModeStep({
    required this.onChanged,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const Spacer(flex: 1),
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.visibility_off_outlined,
              size: 48,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Hide the app?',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Some women need to hide this app from someone close to them.\n\n'
            'If you turn this on, SafeCircle will appear as a calculator. '
            'You can still open the real app by typing your Coercion PIN. '
            'You can set the PIN later in Settings.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(flex: 2),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: () {
                onChanged(true);
                onContinue();
              },
              child: const Text('Yes, hide the app'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton(
              onPressed: () {
                onChanged(false);
                onContinue();
              },
              child: const Text('No, keep it visible'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'You can change this anytime in Settings.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Step 3: Add first contact
// ─────────────────────────────────────────────────────────

class _AddContactStep extends StatelessWidget {
  final TextEditingController nameController;
  final ValueChanged<String> onPhoneChanged;
  final bool isSaving;
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  const _AddContactStep({
    required this.nameController,
    required this.onPhoneChanged,
    required this.isSaving,
    required this.onContinue,
    required this.onSkip,
  });

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
            'Add a trusted contact',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This person will be notified when you trigger an alert. '
            'You can add more contacts later.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Contact name',
              prefixIcon: Icon(Icons.person_outline),
            ),
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 16),
          IntlPhoneField(
            decoration: InputDecoration(
              labelText: 'Phone number',
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            initialCountryCode: 'BR',
            disableLengthCheck: true,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onChanged: (PhoneNumber phone) {
              onPhoneChanged(phone.completeNumber);
            },
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: isSaving ? null : onContinue,
              child: isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('Add contact'),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: onSkip,
              child: const Text('Skip for now'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Step 4: Emergency message
// ─────────────────────────────────────────────────────────

class _EmergencyMessageStep extends StatelessWidget {
  final TextEditingController messageController;
  final VoidCallback onContinue;

  const _EmergencyMessageStep({
    required this.messageController,
    required this.onContinue,
  });

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
            'Emergency message',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This message will be sent to your trusted contacts when you '
            'trigger an alert. Keep it factual and neutral.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: messageController,
            decoration: const InputDecoration(
              labelText: 'Message',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
            maxLines: 4,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 8),
          Text(
            'Tip: Avoid language that could escalate a situation if seen by someone else.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: onContinue,
              child: const Text('Continue'),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Step 6: Completion
// ─────────────────────────────────────────────────────────

class _CompletionStep extends StatelessWidget {
  final VoidCallback onComplete;
  const _CompletionStep({required this.onComplete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const Spacer(flex: 2),
          Container(
            width: 96,
            height: 96,
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
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(
              Icons.shield_rounded,
              size: 48,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'You\'re protected',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'SafeCircle will run in the background 24/7 to keep you safe. '
            'Your safety guardian is always active.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Privacy & encryption guarantee cards
          _InfoChip(
            icon: Icons.lock_outline,
            text: 'All data encrypted end-to-end',
            theme: theme,
          ),
          const SizedBox(height: 10),
          _InfoChip(
            icon: Icons.visibility_off_outlined,
            text: 'No data shared without your consent',
            theme: theme,
          ),
          const SizedBox(height: 10),
          _InfoChip(
            icon: Icons.battery_saver,
            text: 'Optimized for minimal battery usage',
            theme: theme,
          ),

          const Spacer(flex: 3),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton(
              onPressed: onComplete,
              child: const Text('Activate SafeCircle'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'By activating, you authorize SafeCircle to run continuously '
            'in the background for your protection.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final ThemeData theme;

  const _InfoChip({
    required this.icon,
    required this.text,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
