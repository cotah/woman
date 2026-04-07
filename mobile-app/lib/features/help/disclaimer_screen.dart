import 'package:flutter/material.dart';

/// Legal disclaimers screen.
/// Covers: not a replacement for emergency services, no accusation,
/// audio recording responsibility, data handling, liability limits.
class DisclaimerScreen extends StatelessWidget {
  const DisclaimerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Legal disclaimers'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _DisclaimerSection(
            title: 'Not a substitute for emergency services',
            content:
                'SafeCircle is a personal safety communication tool. It is not a substitute '
                'for police, fire, medical, or other emergency services. If you are in '
                'immediate danger, contact your local emergency number (911, 112, or equivalent) '
                'directly.\n\n'
                'SafeCircle does not guarantee that alerts will be delivered in all circumstances. '
                'Network connectivity, device settings, and other factors may affect delivery.',
            theme: theme,
          ),
          _DisclaimerSection(
            title: 'No accusation or judgment',
            content:
                'SafeCircle does not make assessments, accusations, or judgments about any person '
                'or situation. The app transmits factual data (location, time, audio if enabled) '
                'to designated contacts.\n\n'
                'AI audio analysis, if enabled, provides contextual information only and should '
                'not be interpreted as evidence or accusation. Users and their contacts are '
                'responsible for how they interpret and act on the information received.',
            theme: theme,
          ),
          _DisclaimerSection(
            title: 'Audio recording responsibility',
            content:
                'Audio recording laws vary significantly by jurisdiction. Some regions require '
                'all-party consent for recording conversations. It is your sole responsibility '
                'to understand and comply with applicable laws in your jurisdiction.\n\n'
                'SafeCircle provides the technical capability for audio recording but does not '
                'provide legal advice. Enabling audio recording constitutes your acceptance '
                'of responsibility for its legal use.',
            theme: theme,
          ),
          _DisclaimerSection(
            title: 'Data handling and privacy',
            content:
                'Incident data (location, audio, timestamps) is encrypted in transit and at rest. '
                'You control data retention periods and can delete your data at any time.\n\n'
                'SafeCircle does not sell, share, or monetize your personal data. Data is '
                'shared only with contacts you have explicitly designated, according to the '
                'permissions you have configured for each contact.',
            theme: theme,
          ),
          _DisclaimerSection(
            title: 'Coercion PIN feature',
            content:
                'The coercion PIN feature is designed to provide an additional layer of safety. '
                'However, SafeCircle cannot guarantee the effectiveness of this feature in all '
                'situations. It is one tool among many and should be used as part of a broader '
                'personal safety strategy.',
            theme: theme,
          ),
          _DisclaimerSection(
            title: 'Limitation of liability',
            content:
                'SafeCircle is provided "as is" without warranties of any kind. To the maximum '
                'extent permitted by law, SafeCircle and its developers shall not be liable for '
                'any direct, indirect, incidental, special, or consequential damages arising '
                'from the use or inability to use this application.\n\n'
                'This includes but is not limited to: failure to deliver alerts, inaccurate '
                'location data, audio recording failures, or any actions taken by contacts '
                'based on information received through the app.',
            theme: theme,
          ),
          _DisclaimerSection(
            title: 'User responsibility',
            content:
                'By using SafeCircle, you acknowledge that:\n\n'
                '- You will not use the app to make false reports or harass others.\n'
                '- You are responsible for keeping your contact list current.\n'
                '- You will test the app regularly to ensure it functions as expected.\n'
                '- You understand that technology can fail and plan accordingly.\n'
                '- You will comply with all applicable laws in your jurisdiction.',
            theme: theme,
          ),

          const SizedBox(height: 16),

          Text(
            'Last updated: April 2026',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _DisclaimerSection extends StatelessWidget {
  final String title;
  final String content;
  final ThemeData theme;

  const _DisclaimerSection({
    required this.title,
    required this.content,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
