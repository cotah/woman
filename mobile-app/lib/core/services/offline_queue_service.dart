import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Queues operations for retry when network is unavailable.
/// Persists queue to SharedPreferences so it survives app restarts.
class OfflineQueueService extends ChangeNotifier {
  static const _queueKey = 'safecircle_offline_queue';

  List<Map<String, dynamic>> _queue = [];
  bool _isProcessing = false;

  List<Map<String, dynamic>> get queue => List.unmodifiable(_queue);
  int get queueSize => _queue.length;
  bool get hasItems => _queue.isNotEmpty;
  bool get isProcessing => _isProcessing;

  /// Load persisted queue from storage.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw != null) {
      try {
        _queue = (jsonDecode(raw) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        notifyListeners();
      } catch (e) {
        debugPrint('[OfflineQueue] Failed to load queue: $e');
      }
    }
  }

  /// Add an operation to the queue.
  /// [type]: 'incident_create', 'location_update', 'audio_chunk', 'journey_location'
  Future<void> enqueue({
    required String type,
    required Map<String, dynamic> payload,
    String? endpoint,
  }) async {
    _queue.add({
      'type': type,
      'payload': payload,
      'endpoint': endpoint,
      'enqueuedAt': DateTime.now().toIso8601String(),
      'retryCount': 0,
    });
    await _persist();
    notifyListeners();
  }

  /// Process all queued operations. Called when connectivity returns.
  /// [sendFn] is the actual API call function.
  Future<void> processQueue(
    Future<bool> Function(Map<String, dynamic> item) sendFn,
  ) async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;
    notifyListeners();

    final processed = <int>[];

    for (var i = 0; i < _queue.length; i++) {
      try {
        final success = await sendFn(_queue[i]);
        if (success) {
          processed.add(i);
        } else {
          _queue[i]['retryCount'] = (_queue[i]['retryCount'] as int) + 1;
          // Drop after 10 retries.
          if ((_queue[i]['retryCount'] as int) > 10) {
            processed.add(i);
          }
        }
      } catch (e) {
        debugPrint('[OfflineQueue] Failed to process item $i: $e');
        _queue[i]['retryCount'] = (_queue[i]['retryCount'] as int) + 1;
      }
    }

    // Remove processed items in reverse order.
    for (final index in processed.reversed) {
      _queue.removeAt(index);
    }

    await _persist();
    _isProcessing = false;
    notifyListeners();
  }

  /// Clear the entire queue.
  Future<void> clear() async {
    _queue.clear();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueKey, jsonEncode(_queue));
  }
}
