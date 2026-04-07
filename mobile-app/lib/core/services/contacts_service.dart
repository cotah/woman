import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../api/api_endpoints.dart';
import '../models/trusted_contact.dart';

/// Service for managing trusted contacts with backend sync.
class ContactsService extends ChangeNotifier {
  final ApiClient _apiClient;

  List<TrustedContact> _contacts = [];
  bool _isLoading = false;

  ContactsService({required ApiClient apiClient}) : _apiClient = apiClient;

  List<TrustedContact> get contacts => List.unmodifiable(_contacts);
  bool get isLoading => _isLoading;
  int get contactCount => _contacts.length;

  /// Load all contacts from the backend.
  Future<List<TrustedContact>> loadContacts() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiClient.get(ApiEndpoints.contacts);
      final data = response.data;

      if (data is List) {
        _contacts = data
            .map((e) => TrustedContact.fromJson(e as Map<String, dynamic>))
            .toList();
      } else if (data is Map && data['data'] is List) {
        _contacts = (data['data'] as List)
            .map((e) => TrustedContact.fromJson(e as Map<String, dynamic>))
            .toList();
      }

      // Sort by priority.
      _contacts.sort((a, b) => a.priority.compareTo(b.priority));
      return _contacts;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Add a new trusted contact.
  Future<TrustedContact> addContact({
    required String name,
    required String phone,
    String? email,
    String? relationship,
    int priority = 1,
    bool canReceiveSms = true,
    bool canReceivePush = false,
    bool canReceiveVoiceCall = false,
    bool canAccessAudio = false,
    bool canAccessLocation = true,
  }) async {
    final response = await _apiClient.post(
      ApiEndpoints.contacts,
      data: {
        'name': name,
        'phone': phone,
        if (email != null) 'email': email,
        if (relationship != null) 'relationship': relationship,
        'priority': priority,
        'canReceiveSms': canReceiveSms,
        'canReceivePush': canReceivePush,
        'canReceiveVoiceCall': canReceiveVoiceCall,
        'canAccessAudio': canAccessAudio,
        'canAccessLocation': canAccessLocation,
      },
    );

    final contact =
        TrustedContact.fromJson(response.data as Map<String, dynamic>);
    _contacts.add(contact);
    _contacts.sort((a, b) => a.priority.compareTo(b.priority));
    notifyListeners();
    return contact;
  }

  /// Update an existing contact.
  Future<TrustedContact> updateContact(
      String contactId, Map<String, dynamic> updates) async {
    final response = await _apiClient.patch(
      ApiEndpoints.contact(contactId),
      data: updates,
    );

    final updated =
        TrustedContact.fromJson(response.data as Map<String, dynamic>);
    final index = _contacts.indexWhere((c) => c.id == contactId);
    if (index >= 0) {
      _contacts[index] = updated;
    }
    _contacts.sort((a, b) => a.priority.compareTo(b.priority));
    notifyListeners();
    return updated;
  }

  /// Delete a contact.
  Future<void> deleteContact(String contactId) async {
    await _apiClient.delete(ApiEndpoints.contact(contactId));
    _contacts.removeWhere((c) => c.id == contactId);
    notifyListeners();
  }

  /// Reorder contacts by updating priorities.
  Future<void> reorderContacts(List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      final id = orderedIds[i];
      final newPriority = i + 1;
      final contact = _contacts.firstWhere((c) => c.id == id);
      if (contact.priority != newPriority) {
        await updateContact(id, {'priority': newPriority});
      }
    }
  }
}
