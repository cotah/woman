import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Emergency SMS fallback when the network is unavailable.
///
/// ## IMPORTANT: THIS IS NOT FULLY AUTOMATIC
///
/// This service uses `url_launcher` to open the device's native SMS
/// composer app with a pre-filled message and recipients. The user
/// must then tap "Send" in the SMS app to actually send the message.
///
/// Why this limitation exists:
/// - Android and iOS do not allow apps to send SMS silently without
///   user interaction (security restriction).
/// - Truly silent SMS sending requires either:
///   a) Android-only: SEND_SMS permission + SmsManager (requires
///      specific Play Store approval), OR
///   b) A native telephony plugin with platform-specific code.
///
/// Current behavior:
/// 1. Composes an SMS with emergency message + GPS coordinates.
/// 2. Opens the native SMS app with the message pre-filled.
/// 3. User must tap Send. If the user is incapacitated, the SMS
///    will NOT be sent.
///
/// For production:
/// - Consider `telephony` package for Android silent SMS.
/// - Consider a server-side Twilio fallback triggered by missed
///   heartbeats instead of device-side SMS.
class SmsFallbackService {
  /// Open the native SMS composer with an emergency message.
  ///
  /// Returns true if the SMS app was opened successfully.
  /// Returns false if the SMS app could not be opened.
  ///
  /// DOES NOT guarantee the SMS was actually sent — the user must
  /// tap Send in the native SMS app.
  Future<bool> openEmergencySmsComposer({
    required List<String> phones,
    required String userName,
    double? latitude,
    double? longitude,
  }) async {
    if (phones.isEmpty) return false;

    final locationPart = (latitude != null && longitude != null)
        ? '\nLast location: https://maps.google.com/?q=$latitude,$longitude'
        : '';

    final message =
        'EMERGENCY: $userName needs help. '
        'This is an alert from SafeCircle.'
        '$locationPart';

    // Join all phone numbers with comma for multi-recipient SMS.
    final recipients = phones.join(',');
    final uri = Uri(
      scheme: 'sms',
      path: recipients,
      queryParameters: {'body': message},
    );

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return true;
      }
      debugPrint('[SmsFallback] Cannot launch SMS URI');
      return false;
    } catch (e) {
      debugPrint('[SmsFallback] Failed to open SMS composer: $e');
      return false;
    }
  }
}
