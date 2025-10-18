// File: services/tnc_service.dart

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'aprs_parser.dart';

// KISS Protocol Constants
const int FEND = 0xC0; // Frame End
const int FESC = 0xDB; // Frame Escape
const int TFEND = 0xDC; // Transposed Frame End
const int TFESC = 0xDD; // Transposed Frame Escape
const int KISS_CMD_DATA = 0x00;

/// Differentiates where a transmitted packet came from.
enum PacketSource { digipeat, iGate, beacon }

/// Simple class to bundle a transmitted packet with its source.
class TransmittedPacket {
  final AprsPacket packet;
  final PacketSource source;
  TransmittedPacket(this.packet, this.source);
}

class TncService {
  // --- Private State ---
  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _dataSubscription;
  List<int> _buffer = [];

  // --- Configuration State ---
  String _myCallsign = 'N0CALL';
  int _mySSID = 1;
  bool _isDigipeaterEnabled = true;
  static const _callsignPrefKey = 'user_callsign';

  // --- Stream Controllers ---
  final _systemLogController = StreamController<String>.broadcast();
  final _rxPacketLogController = StreamController<AprsPacket>.broadcast();
  final _txPacketLogController = StreamController<TransmittedPacket>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();
  final _deviceListController = StreamController<List<BluetoothDevice>>.broadcast();
  final _isScanningController = StreamController<bool>.broadcast();
  final _initialCallsignController = StreamController<String>.broadcast();

  // --- Public Streams ---
  Stream<String> get systemLogs => _systemLogController.stream;
  Stream<AprsPacket> get rxPacketLogs => _rxPacketLogController.stream;
  Stream<TransmittedPacket> get txPacketLogs => _txPacketLogController.stream;
  Stream<bool> get isConnectedStream => _connectionStatusController.stream;
  Stream<List<BluetoothDevice>> get deviceStream => _deviceListController.stream;
  Stream<bool> get isScanningStream => _isScanningController.stream;
  Stream<String> get initialCallsign => _initialCallsignController.stream;

  TncService() {
    _connectionStatusController.add(false);
    _isScanningController.add(false);
    _loadCallsign();
  }

  // --- SharedPreferences Logic ---
  Future<void> _loadCallsign() async {
    final prefs = await SharedPreferences.getInstance();
    final callsign = prefs.getString(_callsignPrefKey) ?? 'N0CALL-1';
    setCallsign(callsign);
    _initialCallsignController.add(callsign);
  }

  Future<void> _saveCallsign(String callsignSsid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_callsignPrefKey, callsignSsid);
  }

  // --- Public Configuration Methods ---
  void setCallsign(String callsignSsid) {
    if (callsignSsid.contains('-')) {
      var parts = callsignSsid.split('-');
      _myCallsign = parts[0].toUpperCase();
      _mySSID = int.tryParse(parts[1]) ?? 0;
    } else {
      _myCallsign = callsignSsid.toUpperCase();
      _mySSID = 0;
    }
    _saveCallsign(callsignSsid);
    _systemLogController.add('Callsign set to $_myCallsign-$_mySSID');
  }

  void setDigipeaterEnabled(bool enabled) {
    _isDigipeaterEnabled = enabled;
    _systemLogController.add('Digipeater ${enabled ? "enabled" : "disabled"}.');
  }

  // --- Connection Methods ---
  Future<void> getPairedDevices() async {
    _isScanningController.add(true);
    _systemLogController.add('Scanning for paired devices...');
    try {
      List<BluetoothDevice> devices =
          await FlutterBluetoothSerial.instance.getBondedDevices();
      _deviceListController.add(devices);
      _systemLogController.add('Scan complete. Found ${devices.length} devices.');
    } catch (e) {
      _systemLogController.add('Error scanning: $e');
    } finally {
      _isScanningController.add(false);
    }
  }

  Future<void> connect(BluetoothDevice device) async {
    _systemLogController.add('Connecting to ${device.name ?? device.address}...');
    try {
      _connection = await BluetoothConnection.toAddress(device.address);
      _connectionStatusController.add(true);
      _systemLogController.add('Connection established successfully.');
      _dataSubscription = _connection!.input!.listen(
        _onDataReceived,
        onDone: () => disconnect(remote: true),
        onError: (e) {
          _systemLogController.add('Stream Error: $e');
          disconnect();
        },
      );
    } catch (e) {
      _systemLogController.add('Error connecting: $e');
      _connectionStatusController.add(false);
    }
  }

  Future<void> disconnect({bool remote = false}) async {
    if (remote) {
      _systemLogController.add('Device disconnected remotely.');
    } else {
      _systemLogController.add('Disconnecting...');
    }
    await _dataSubscription?.cancel();
    await _connection?.close();
    _connection = null;
    _dataSubscription = null;
    _buffer.clear();
    _connectionStatusController.add(false);
    if (!remote) _systemLogController.add('Connection closed.');
  }

  // --- Data Processing and Logic ---
  void _onDataReceived(Uint8List data) {
    _buffer.addAll(data);
    _processBuffer();
  }

  void _processBuffer() {
    while (_buffer.contains(FEND)) {
      int frameStartIndex = _buffer.indexOf(FEND);
      if (frameStartIndex > 0) _buffer.removeRange(0, frameStartIndex);
      _buffer.removeAt(0);
      int frameEndIndex = _buffer.indexOf(FEND);
      if (frameEndIndex == -1) {
        _buffer.insert(0, FEND);
        break;
      }
      Uint8List rawFrame = Uint8List.fromList(_buffer.sublist(0, frameEndIndex));
      _buffer.removeRange(0, frameEndIndex);
      if (rawFrame.isEmpty) continue;

      int command = rawFrame[0] & 0x0F;
      if (command == KISS_CMD_DATA) {
        Uint8List ax25Frame = _unescapeKISS(rawFrame.sublist(1));
        AprsPacket? packet = AprsParser.parse(ax25Frame);
        if (packet != null) {
          _rxPacketLogController.add(packet);
          _processDigipeat(packet);
        }
      }
    }
  }

  void _processDigipeat(AprsPacket packet) {
    if (!_isDigipeaterEnabled) return;
    if (packet.source.callsign == _myCallsign) return;

    List<Ax25Address> newPath = [];
    bool pathModified = false;
    bool foundMyCallsign = false;

    for (int i = 0; i < packet.path.length; i++) {
      Ax25Address hop = packet.path[i];
      newPath.add(hop);

      if (hop.callsign == _myCallsign) {
        foundMyCallsign = true;
      }

      if (!hop.hasBeenDigipeated && !pathModified) {
        if (hop.matches('WIDE1-1')) {
          hop.hasBeenDigipeated = true;
          newPath.add(Ax25Address(
            callsign: _myCallsign,
            ssid: _mySSID,
            hasBeenDigipeated: true,
          ));
          pathModified = true;
        } else if (hop.matches('WIDE2-1')) {
          hop.hasBeenDigipeated = true;
          newPath.add(Ax25Address(
            callsign: _myCallsign,
            ssid: _mySSID,
            hasBeenDigipeated: true,
          ));
          pathModified = true;
        } else if (hop.matches('WIDE2-2')) {
          hop.callsign = 'WIDE2';
          hop.ssid = 1;
          newPath.insert(
              newPath.length - 1,
              Ax25Address(
                callsign: _myCallsign,
                ssid: _mySSID,
                hasBeenDigipeated: true,
              ));
          pathModified = true;
        }
      }
    }

    if (pathModified && !foundMyCallsign) {
      AprsPacket digiPacket = AprsPacket(
        source: packet.source,
        destination: packet.destination,
        path: newPath,
        payload: packet.payload,
        originalFrame: packet.originalFrame,
      );
      transmitPacket(digiPacket, source: PacketSource.digipeat);
    }
  }

  /// Public method to transmit any APRS packet (from digi, igate, or beacon).
  Future<void> transmitPacket(AprsPacket packet, {required PacketSource source}) async {
    if (_connection == null || !_connection!.isConnected) {
      _systemLogController.add('TX Error: Not connected.');
      return;
    }

    try {
      Uint8List ax25Frame = AprsParser.encode(packet);
      Uint8List kissFrame = _escapeKISS(ax25Frame, command: KISS_CMD_DATA);

      _connection!.output.add(kissFrame);
      await _connection!.output.allSent;

      _txPacketLogController.add(TransmittedPacket(packet, source));
    } catch (e) {
      _systemLogController.add('TX Error: $e');
    }
  }

  Uint8List _escapeKISS(Uint8List ax25Frame, {required int command}) {
    List<int> kissFrame = [];
    kissFrame.add(FEND);
    kissFrame.add(command);

    for (int byte in ax25Frame) {
      if (byte == FEND) {
        kissFrame.add(FESC);
        kissFrame.add(TFEND);
      } else if (byte == FESC) {
        kissFrame.add(FESC);
        kissFrame.add(TFESC);
      } else {
        kissFrame.add(byte);
      }
    }
    kissFrame.add(FEND);
    return Uint8List.fromList(kissFrame);
  }

  Uint8List _unescapeKISS(Uint8List frame) {
    List<int> unescaped = [];
    for (int i = 0; i < frame.length; i++) {
      if (frame[i] == FESC) {
        i++;
        if (i < frame.length) {
          if (frame[i] == TFEND) {
            unescaped.add(FEND);
          } else if (frame[i] == TFESC) {
            unescaped.add(FESC);
          }
        }
      } else {
        unescaped.add(frame[i]);
      }
    }
    return Uint8List.fromList(unescaped);
  }

  void dispose() {
    _systemLogController.close();
    _rxPacketLogController.close();
    _txPacketLogController.close();
    _connectionStatusController.close();
    _deviceListController.close();
    _isScanningController.close();
    _initialCallsignController.close();
    disconnect();
  }
}