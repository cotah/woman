import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../core/services/contacts_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/storage/secure_storage.dart';
import 'permissions_step.dart';
import 'voice_activation_step.dart';

/// Multi-step onboarding flow:
/// 0 - Welcome
/// 1 - Permissions (location, notifications, microphone)
/// 2 - Voice activation setup (custom word + voice recording)
/// 3 - Add first trusted contact
/// 4 - Set emergency message
/// 5 - Completion
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _currentStep = 0;
  static const _totalSteps = 6;

  // Permission state
  bool _locationGranted = false;
  bool _notificationsGranted = false;
  bool _microphoneGranted = false;

  // Contact form
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  bool _isSavingContact = false;

  // Voice activation
  String _activationWord = '';
  List<String> _voiceRecordingPaths = [];

  // Emergency message
  final _emergencyMessageController = TextEditingController(
    text: 'I may be in danger. Please check on me or contact emergency services.',
  );

  @override
  void initState() {
    super.initState();
    _checkExistingPermissions();
  }

  Future<void> _checkExistingPermissions() async {
    final locPerm = await Geolocator.checkPermission();
    final micPerm = await Permission.microphone.status;
    final notifPerm = await Permission.notification.status;

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
    _pageController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
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
      return;
    }

    if (mounted) {
      setState(() {
        _locationGranted = permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse;
      });
    }
  }

  Future<void> _requestNotifications() async {
    final status = await Permission.notification.request();

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
      return;
    }

    if (mounted) {
      setState(() => _notificationsGranted = status.isGranted);
    }
  }

  Future<void> _requestMicrophone() async {
    final status = await Permission.microphone.request();

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
      return;
    }

    if (mounted) {
      setState(() => _microphoneGranted = status.isGranted);
    }
  }

  Future<void> _saveContact() async {
    final name = _contactNameController.text.trim();
    final phone = _contactPhoneController.text.trim();

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
      await storage.setOnboardingComplete();
      if (_activationWord.isNotEmpty) {
        await storage.setActivationWord(_activationWord);
      }
    } catch (e) {
      debugPrint('[Onboarding] Failed to save completion flag: $e');
    }
    if (mounted) context.go('/home');
  }

  void _onVoiceComplete(String word, List<String> paths) {
    _activationWord = word;
    _voiceRecordingPaths = paths;
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
                  VoiceActivationStep(
                    onContinue: _nextStep,
                    onSkip: _nextStep,
                    onComplete: _onVoiceComplete,
                  ),
                  _AddContactStep(
                    nameController: _contactNameController,
                    phoneController: _contactPhoneController,
                    isSaving: _isSavingContact,
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
// Step 2: Add first contact
// ─────────────────────────────────────────────────────────

class _AddContactStep extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final bool isSaving;
  final VoidCallback onContinue;
  final VoidCallback onSkip;

  const _AddContactStep({
    required this.nameController,
    required this.phoneController,
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
          TextField(
            controller: phoneController,
            decoration: const InputDecoration(
              labelText: 'Phone number',
              prefixIcon: Icon(Icons.phone_outlined),
              hintText: '+55 11 99999-0000',
            ),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
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
// Step 3: Emergency message
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
// Step 4: Completion
// ─────────────────────────────────────────────────────────

class _CompletionStep extends StatelessWidget {
  final VoidCallback onComplete;
  const _CompletionStep({required this.onComplete});

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
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_rounded,
              size: 48,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'You\'re all set',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Your safety network is configured. You can adjust all settings '
            'at any time. We recommend testing the alert flow from the dashboard.',
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
              onPressed: onComplete,
              child: const Text('Go to dashboard'),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
