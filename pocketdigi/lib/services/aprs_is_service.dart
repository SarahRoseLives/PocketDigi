// File: services/aprs_is_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AprsIsService {
  final String _server = 'rotate.aprs.net';
  final int _port = 14580;
  Socket? _socket;

  final _systemLogController = StreamController<String>.broadcast();
  final _incomingPacketsController = StreamController<String>.broadcast();

  Stream<String> get systemLogs => _systemLogController.stream;
  Stream<String> get incomingPackets => _incomingPacketsController.stream;

  /// Generates the APRS-IS passcode for a given callsign.
  static int generatePasscode(String callsign) {
    String call = callsign.split('-')[0].toUpperCase();
    int hash = 0x73e2;
    for (int i = 0; i < call.length; i += 2) {
      hash ^= (call.codeUnitAt(i) << 8);
      if (i + 1 < call.length) {
        hash ^= call.codeUnitAt(i + 1);
      }
    }
    return hash & 0x7FFF;
  }

  /// Connects to APRS-IS using a location-based filter.
  Future<void> connect({
    required String callsign,
    required double latitude,
    required double longitude,
    int radiusKm = 50, // Default to 50km radius
  }) async {
    int passcode = generatePasscode(callsign);
    // Construct a valid filter (e.g., "r/41.123/-80.456/50")
    String filter = 'r/${latitude.toStringAsFixed(4)}/${longitude.toStringAsFixed(4)}/$radiusKm';
    String login = 'user $callsign pass $passcode vers PocketDigi 1.0 filter $filter\n';

    try {
      _systemLogController.add('Connecting to APRS-IS with filter: $filter');
      _socket = await Socket.connect(_server, _port);
      _systemLogController.add('Connected to $_server:$_port');

      _socket!.listen(
        _onDataReceived,
        onError: (e) {
          _systemLogController.add('APRS-IS Error: $e');
          disconnect();
        },
        onDone: () {
          _systemLogController.add('APRS-IS disconnected.');
          disconnect();
        },
      );

      _socket!.write(login);
      await _socket!.flush();
    } catch (e) {
      _systemLogController.add('APRS-IS connection failed: $e');
    }
  }

  void _onDataReceived(List<int> data) {
    String response = utf8.decode(data);
    response.split('\n').forEach((line) {
      line = line.trim();
      if (line.isEmpty) return;
      if (line.startsWith('#')) {
        _systemLogController.add('APRS-IS: $line'); // Log server messages
      } else {
        _incomingPacketsController.add(line); // Pass packet to UI
      }
    });
  }

  /// Sends a raw APRS packet string to the IS server.
  void sendPacket(String aprsString) {
    if (_socket != null) {
      try {
        _socket!.write('$aprsString\n');
        _socket!.flush();
      } catch (e) {
        _systemLogController.add('APRS-IS send error: $e');
      }
    }
  }

  void disconnect() {
    _socket?.close();
    _socket = null;
  }

  void dispose() {
    disconnect();
    _systemLogController.close();
    _incomingPacketsController.close();
  }
}