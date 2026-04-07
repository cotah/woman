import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config/app_config.dart';
import '../storage/secure_storage.dart';

/// WebSocket client for real-time incident updates.
///
/// Uses socket_io_client to match the backend NestJS Socket.IO gateway.
/// The backend gateway lives at namespace '/incidents' and uses Socket.IO
/// protocol (not raw WebSockets). Previous implementation used
/// web_socket_channel which is INCOMPATIBLE with Socket.IO.
class WebSocketService extends ChangeNotifier {
  final SecureStorage _secureStorage;

  io.Socket? _socket;
  bool _isConnected = false;
  String? _currentIncidentId;

  /// Stream controllers for different event types.
  final StreamController<Map<String, dynamic>> _incidentUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _locationUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _riskUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _alertUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _contactResponseController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _timelineEventController =
      StreamController<Map<String, dynamic>>.broadcast();

  WebSocketService({required SecureStorage secureStorage})
      : _secureStorage = secureStorage;

  bool get isConnected => _isConnected;

  Stream<Map<String, dynamic>> get incidentUpdates =>
      _incidentUpdateController.stream;
  Stream<Map<String, dynamic>> get locationUpdates =>
      _locationUpdateController.stream;
  Stream<Map<String, dynamic>> get riskUpdates =>
      _riskUpdateController.stream;
  Stream<Map<String, dynamic>> get alertUpdates =>
      _alertUpdateController.stream;
  Stream<Map<String, dynamic>> get contactResponses =>
      _contactResponseController.stream;
  Stream<Map<String, dynamic>> get timelineEvents =>
      _timelineEventController.stream;

  /// Connect to the Socket.IO server at the /incidents namespace.
  Future<void> connect() async {
    if (_isConnected && _socket != null) return;

    final token = await _secureStorage.getAccessToken();
    if (token == null) {
      debugPrint('[WebSocket] No access token, cannot connect');
      return;
    }

    final wsUrl = AppConfig.instance.wsUrl;

    _socket = io.io(
      '$wsUrl/incidents',
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setAuth({'token': token})
          .setQuery({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(30000)
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[WebSocket] Connected');
      _isConnected = true;
      notifyListeners();

      // Re-join incident room if we had one.
      if (_currentIncidentId != null) {
        joinIncident(_currentIncidentId!);
      }
    });

    _socket!.onDisconnect((_) {
      debugPrint('[WebSocket] Disconnected');
      _isConnected = false;
      notifyListeners();
    });

    _socket!.onConnectError((error) {
      debugPrint('[WebSocket] Connection error: $error');
      _isConnected = false;
      notifyListeners();
    });

    _socket!.onError((error) {
      debugPrint('[WebSocket] Error: $error');
    });

    // Register event listeners matching the backend gateway's emit events.
    _socket!.on('incident:update', (data) {
      final payload = _toMap(data);
      if (payload != null) _incidentUpdateController.add(payload);
    });

    _socket!.on('location:update', (data) {
      final payload = _toMap(data);
      if (payload != null) _locationUpdateController.add(payload);
    });

    _socket!.on('risk:update', (data) {
      final payload = _toMap(data);
      if (payload != null) _riskUpdateController.add(payload);
    });

    _socket!.on('alert:update', (data) {
      final payload = _toMap(data);
      if (payload != null) _alertUpdateController.add(payload);
    });

    _socket!.on('contact:response', (data) {
      final payload = _toMap(data);
      if (payload != null) _contactResponseController.add(payload);
    });

    _socket!.on('timeline:event', (data) {
      final payload = _toMap(data);
      if (payload != null) _timelineEventController.add(payload);
    });

    _socket!.on('joined', (data) {
      debugPrint('[WebSocket] Joined room: $data');
    });

    _socket!.on('error', (data) {
      debugPrint('[WebSocket] Server error: $data');
    });

    _socket!.connect();
  }

  /// Disconnect from the Socket.IO server.
  Future<void> disconnect() async {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
    _currentIncidentId = null;
    notifyListeners();
  }

  /// Join an incident room to receive real-time updates.
  void joinIncident(String incidentId) {
    if (_socket == null || !_isConnected) {
      _currentIncidentId = incidentId;
      return;
    }

    _currentIncidentId = incidentId;
    _socket!.emit('join:incident', {'incidentId': incidentId});
  }

  /// Leave an incident room.
  void leaveIncident(String incidentId) {
    if (_socket == null) return;

    if (_currentIncidentId == incidentId) {
      _currentIncidentId = null;
    }

    _socket!.emit('leave:incident', {'incidentId': incidentId});
  }

  /// Convert Socket.IO data to a Map. Socket.IO can deliver data
  /// as Map, List, or other types depending on how the server emits.
  Map<String, dynamic>? _toMap(dynamic data) {
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    debugPrint('[WebSocket] Unexpected data type: ${data.runtimeType}');
    return null;
  }

  @override
  void dispose() {
    disconnect();
    _incidentUpdateController.close();
    _locationUpdateController.close();
    _riskUpdateController.close();
    _alertUpdateController.close();
    _contactResponseController.close();
    _timelineEventController.close();
    super.dispose();
  }
}
