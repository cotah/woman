import 'dart:convert';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart';
import '../storage/secure_storage.dart';
import '../services/incident_service.dart';

/// Coercion PIN handler.
///
/// SAFETY-CRITICAL: When a user enters their coercion PIN instead of their
/// normal PIN, the device UI must appear as if everything is cancelled/normal,
/// while the backend silently escalates the incident.
///
/// Flow:
/// 1. User enters a PIN during an active incident or countdown.
/// 2. This handler validates the PIN locally (SHA256 hash comparison).
/// 3. If coercion PIN: calls incidentService.secretCancelIncident() which
///    sends `isSecretCancel: true` to backend BUT does NOT stop local
///    tracking (location, audio, websocket remain active).
/// 4. If normal PIN: calls incidentService.cancelIncident() which genuinely
///    stops everything.
/// 5. The UI layer uses the CoercionResult to decide what screen to show.
///
/// IMPORTANT: secretCancelIncident() is specifically designed to NOT call
/// _cleanupActiveIncident(). Location tracking, audio recording, and
/// websocket connections remain active even though the UI shows "cancelled".
class CoercionHandler {
  final SecureStorage _secureStorage;

  CoercionHandler({required SecureStorage secureStorage})
      : _secureStorage = secureStorage;

  /// Check if a coercion PIN has been set up.
  Future<bool> hasCoercionPin() async {
    final hash = await _secureStorage.getCoercionPinHash();
    return hash != null && hash.isNotEmpty;
  }

  /// Verify if the entered PIN is the coercion PIN.
  /// Returns true if it matches the coercion PIN.
  Future<bool> isCoercionPin(String enteredPin) async {
    final storedHash = await _secureStorage.getCoercionPinHash();
    if (storedHash == null || storedHash.isEmpty) return false;

    final enteredHash = _hashPin(enteredPin);
    return enteredHash == storedHash;
  }

  /// Verify if the entered PIN is the normal (non-coercion) cancel PIN.
  /// Returns true if it does NOT match the coercion PIN (i.e., it is
  /// the normal cancel).
  Future<bool> isNormalPin(String enteredPin) async {
    final isCoercion = await isCoercionPin(enteredPin);
    return !isCoercion;
  }

  /// Handle a PIN entry during an active incident.
  ///
  /// SAFETY-CRITICAL behavior:
  /// - Coercion PIN → calls secretCancelIncident (keeps tracking alive,
  ///   only changes UI flag). Returns [CoercionResult.coercionEscalated].
  /// - Normal PIN → calls cancelIncident (genuinely stops everything).
  ///   Returns [CoercionResult.normallyCancelled].
  ///
  /// Both results have [shouldShowCancelledUI] == true, so the UI looks
  /// identical to an attacker in either case.
  Future<CoercionResult> handlePinEntry(
    String enteredPin,
    String incidentId,
    IncidentService incidentService,
  ) async {
    final isCoercion = await isCoercionPin(enteredPin);

    if (isCoercion) {
      // COERCION: Send secret cancel to backend (escalates silently).
      // incidentService.secretCancelIncident does NOT stop tracking.
      try {
        await incidentService.secretCancelIncident(incidentId);
        return CoercionResult.coercionEscalated;
      } catch (e) {
        debugPrint('[CoercionHandler] Secret cancel failed: $e');
        // Even on failure, show cancelled UI to protect the user.
        return CoercionResult.coercionEscalated;
      }
    } else {
      // NORMAL: Genuinely cancel the incident and stop tracking.
      try {
        await incidentService.cancelIncident(incidentId, reason: 'User PIN cancel');
        return CoercionResult.normallyCancelled;
      } catch (e) {
        debugPrint('[CoercionHandler] Normal cancel failed: $e');
        return CoercionResult.error;
      }
    }
  }

  /// Save a new coercion PIN (hashed locally).
  Future<void> setCoercionPin(String pin) async {
    final hash = _hashPin(pin);
    await _secureStorage.setCoercionPinHash(hash);
  }

  /// Remove the coercion PIN.
  Future<void> clearCoercionPin() async {
    await _secureStorage.deleteCoercionPinHash();
  }

  String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }
}

/// Result of a coercion PIN check.
enum CoercionResult {
  /// Normal PIN entered - incident was genuinely cancelled.
  normallyCancelled,

  /// Coercion PIN entered - UI shows cancelled but backend escalated.
  /// Location, audio, and websocket remain ACTIVE on this device.
  coercionEscalated,

  /// An error occurred during the operation.
  error,
}

extension CoercionResultExtension on CoercionResult {
  /// Whether the UI should show a "cancelled" confirmation.
  /// Both normal and coercion results should show the same UI.
  bool get shouldShowCancelledUI =>
      this == CoercionResult.normallyCancelled ||
      this == CoercionResult.coercionEscalated;
}
