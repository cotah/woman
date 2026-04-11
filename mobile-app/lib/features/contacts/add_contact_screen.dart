import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';
import 'package:provider/provider.dart';

import '../../core/models/trusted_contact.dart';
import '../../core/services/contacts_service.dart';

/// Form to add or edit a trusted contact with all permission settings.
class AddContactScreen extends StatefulWidget {
  final String? contactId;

  const AddContactScreen({super.key, this.contactId});

  bool get isEditing => contactId != null;

  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  String _fullPhoneNumber = '';
  String _initialPhone = '';
  String _relationship = 'Friend';
  bool _isLoading = false;
  bool _isDeleting = false;

  // Contact permissions (aligned with backend TrustedContact entity)
  bool _canReceiveSms = true;
  bool _canReceivePush = false;
  bool _canReceiveVoiceCall = false;
  bool _canAccessAudio = false;
  bool _canAccessLocation = true;

  static const _relationships = [
    'Partner',
    'Spouse',
    'Parent',
    'Sibling',
    'Friend',
    'Colleague',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      _loadContact();
    }
  }

  void _loadContact() {
    final contactsService = context.read<ContactsService>();
    final contact = contactsService.contacts
        .where((c) => c.id == widget.contactId)
        .firstOrNull;

    if (contact != null) {
      _nameController.text = contact.name;
      _fullPhoneNumber = contact.phone;
      _initialPhone = contact.phone;
      _emailController.text = contact.email ?? '';
      _relationship = contact.relationship ?? 'Friend';
      _canReceiveSms = contact.canReceiveSms;
      _canReceivePush = contact.canReceivePush;
      _canReceiveVoiceCall = contact.canReceiveVoiceCall;
      _canAccessAudio = contact.canAccessAudio;
      _canAccessLocation = contact.canAccessLocation;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final contactsService = context.read<ContactsService>();
      final data = {
        'name': _nameController.text.trim(),
        'phone': _fullPhoneNumber,
        'relationship': _relationship,
        'canReceiveSms': _canReceiveSms,
        'canReceivePush': _canReceivePush,
        'canReceiveVoiceCall': _canReceiveVoiceCall,
        'canAccessAudio': _canAccessAudio,
        'canAccessLocation': _canAccessLocation,
      };

      final email = _emailController.text.trim();
      if (email.isNotEmpty) data['email'] = email;

      if (widget.isEditing) {
        await contactsService.updateContact(widget.contactId!, data);
      } else {
        await contactsService.addContact(
          name: data['name'] as String,
          phone: data['phone'] as String,
          email: email.isNotEmpty ? email : null,
          relationship: _relationship,
          canReceiveSms: _canReceiveSms,
          canReceivePush: _canReceivePush,
          canReceiveVoiceCall: _canReceiveVoiceCall,
          canAccessAudio: _canAccessAudio,
          canAccessLocation: _canAccessLocation,
        );
      }

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save contact: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _isDeleting = true);
    try {
      final contactsService = context.read<ContactsService>();
      await contactsService.deleteContact(widget.contactId!);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove contact: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit contact' : 'Add contact'),
        actions: [
          if (widget.isEditing)
            IconButton(
              onPressed: _isDeleting ? null : _confirmDelete,
              icon: _isDeleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
              tooltip: 'Remove contact',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),

              // Basic info section
              Text(
                'Contact information',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),

              IntlPhoneField(
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  counterText: '',
                ),
                initialCountryCode: 'BR',
                initialValue: _initialPhone.isNotEmpty
                    ? _initialPhone.replaceFirst(RegExp(r'^\+\d+\s?'), '')
                    : null,
                disableLengthCheck: false,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                onChanged: (PhoneNumber phone) {
                  _fullPhoneNumber = phone.completeNumber;
                },
                validator: (PhoneNumber? phone) {
                  if (phone == null || phone.number.isEmpty) {
                    return 'Phone number is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _relationship,
                decoration: const InputDecoration(
                  labelText: 'Relationship',
                  prefixIcon: Icon(Icons.favorite_outline),
                ),
                items: _relationships
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _relationship = v);
                },
              ),

              const SizedBox(height: 32),

              // Permissions section
              Text(
                'Alert channels',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'How this contact is notified during an alert.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),

              _PermissionSwitch(
                title: 'SMS alerts',
                subtitle: 'Receive emergency SMS during an alert.',
                value: _canReceiveSms,
                onChanged: (v) => setState(() => _canReceiveSms = v),
              ),
              _PermissionSwitch(
                title: 'Push notifications',
                subtitle: 'Receive push notifications on their phone.',
                value: _canReceivePush,
                onChanged: (v) => setState(() => _canReceivePush = v),
              ),
              _PermissionSwitch(
                title: 'Voice call',
                subtitle: 'Receive an automated voice call during escalation.',
                value: _canReceiveVoiceCall,
                onChanged: (v) => setState(() => _canReceiveVoiceCall = v),
              ),

              const Divider(height: 32),

              Text(
                'Data access',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'What this contact can see during an alert.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),

              _PermissionSwitch(
                title: 'Live location',
                subtitle: 'See your real-time location during an alert.',
                value: _canAccessLocation,
                onChanged: (v) => setState(() => _canAccessLocation = v),
              ),
              _PermissionSwitch(
                title: 'Audio recordings',
                subtitle: 'Access audio captured during an alert.',
                value: _canAccessAudio,
                onChanged: (v) => setState(() => _canAccessAudio = v),
              ),

              const SizedBox(height: 32),

              // Save button
              SizedBox(
                height: 56,
                child: FilledButton(
                  onPressed: _isLoading ? null : _save,
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(widget.isEditing ? 'Save changes' : 'Add contact'),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove contact'),
        content: const Text(
          'This person will no longer be notified during alerts. '
          'You can add them again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _delete();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _PermissionSwitch extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _PermissionSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }
}
