import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Help screen with how it works, FAQ, and disclaimers link.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Help'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // How it works
          Text(
            'How SafeCircle works',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),

          _StepCard(
            number: '1',
            title: 'Set up your network',
            description:
                'Add trusted contacts who will be notified during an alert. '
                'You choose what information each contact receives.',
            icon: Icons.people_outline,
            theme: theme,
          ),
          _StepCard(
            number: '2',
            title: 'Trigger an alert',
            description:
                'Long press the main button or use a configured trigger. '
                'A silent countdown begins before contacts are notified.',
            icon: Icons.touch_app_outlined,
            theme: theme,
          ),
          _StepCard(
            number: '3',
            title: 'Contacts are notified',
            description:
                'Your trusted contacts receive a message with your current location. '
                'Audio recording and AI analysis can be enabled optionally.',
            icon: Icons.notifications_outlined,
            theme: theme,
          ),
          _StepCard(
            number: '4',
            title: 'Cancel or resolve',
            description:
                'Cancel during the countdown with a secret gesture. '
                'When safe, end the alert to notify contacts.',
            icon: Icons.check_circle_outline,
            theme: theme,
          ),

          const SizedBox(height: 32),

          // FAQ
          Text(
            'Frequently asked questions',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),

          _FaqItem(
            question: 'What happens if I trigger an alert by accident?',
            answer:
                'You have a configurable countdown period (3-30 seconds) to cancel '
                'before contacts are notified. Use the secret cancel gesture or '
                'enter your PIN to stop the alert.',
          ),
          _FaqItem(
            question: 'What is the coercion PIN?',
            answer:
                'If someone forces you to cancel an alert, entering the coercion PIN '
                'shows a fake "cancelled" screen. The alert continues running and '
                'your contacts are still receiving updates.',
          ),
          _FaqItem(
            question: 'Is audio recording legal?',
            answer:
                'Audio recording laws vary by jurisdiction. Some regions require '
                'all parties to consent to recording. Check your local laws. '
                'SafeCircle does not provide legal advice.',
          ),
          _FaqItem(
            question: 'How is my data stored?',
            answer:
                'Data is encrypted at rest and in transit. You control how long '
                'incident data is retained in Privacy settings. You can export '
                'or delete your data at any time.',
          ),
          _FaqItem(
            question: 'Does this replace emergency services?',
            answer:
                'No. SafeCircle is a personal safety tool that notifies trusted contacts. '
                'It is not a replacement for calling emergency services (police, fire, medical). '
                'Always contact 911/112/equivalent when in immediate danger.',
          ),
          _FaqItem(
            question: 'Can I test the system without alerting anyone?',
            answer:
                'Yes. Use Test Mode from the dashboard to simulate the entire alert flow '
                'without sending real notifications to your contacts.',
          ),

          const SizedBox(height: 24),

          // Links
          OutlinedButton(
            onPressed: () => context.push('/disclaimer'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
            ),
            child: const Text('Legal disclaimers'),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String number;
  final String title;
  final String description;
  final IconData icon;
  final ThemeData theme;

  const _StepCard({
    required this.number,
    required this.title,
    required this.description,
    required this.icon,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
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
      ),
    );
  }
}

class _FaqItem extends StatefulWidget {
  final String question;
  final String answer;

  const _FaqItem({required this.question, required this.answer});

  @override
  State<_FaqItem> createState() => _FaqItemState();
}

class _FaqItemState extends State<_FaqItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 24,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 12),
                Text(
                  widget.answer,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
