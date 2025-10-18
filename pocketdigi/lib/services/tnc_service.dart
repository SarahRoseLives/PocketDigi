// File: services/tnc_service.dart

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'aprs_parser.dart';

// KISS Protocol Constants
const int FEND = 0xC0; // Frame End
const int FESC = 0xDB; // Frame Escape
const int TFEND = 0xDC; // Transposed Frame End
const int TFESC = 0xDD; // Transposed Frame Escape

class TncService {
  // --- Private State ---
  BluetoothConnection? _connection;
  StreamSubscription<Uint8List>? _dataSubscription;
  List<int> _buffer = [];

  // --- Stream Controllers for UI Communication ---
  final _systemLogController = StreamController<String>.broadcast();
  final _packetLogController = StreamController<AprsPacket>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();
  final _deviceListController = StreamController<List<BluetoothDevice>>.broadcast();
  final _isScanningController = StreamController<bool>.broadcast();

  // --- Public Streams for the UI to consume ---
  Stream<String> get systemLogs => _systemLogController.stream;
  Stream<AprsPacket> get packetLogs => _packetLogController.stream;
  Stream<bool> get isConnectedStream => _connectionStatusController.stream;
  Stream<List<BluetoothDevice>> get deviceStream => _deviceListController.stream;
  Stream<bool> get isScanningStream => _isScanningController.stream;

  TncService() {
    // Initial status
    _connectionStatusController.add(false);
    _isScanningController.add(false);
  }

  /// Fetches paired devices and pushes them to the stream.
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

  /// Connects to the given device.
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

  /// Disconnects from the current device.
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

  /// Handles incoming raw data from the Bluetooth stream.
  void _onDataReceived(Uint8List data) {
    _buffer.addAll(data);
    _processBuffer();
  }

  /// Processes the buffer to find and decode complete KISS frames.
  void _processBuffer() {
    while (_buffer.contains(FEND)) {
      int frameStartIndex = _buffer.indexOf(FEND);
      if (frameStartIndex > 0) {
        // Discard data before the first FEND
        _buffer.removeRange(0, frameStartIndex);
      }
      _buffer.removeAt(0); // Remove the starting FEND

      int frameEndIndex = _buffer.indexOf(FEND);
      if (frameEndIndex == -1) {
        // Incomplete frame, wait for more data
        _buffer.insert(0, FEND); // Put back the start FEND
        break;
      }

      // Extract a complete frame
      Uint8List rawFrame = Uint8List.fromList(_buffer.sublist(0, frameEndIndex));
      _buffer.removeRange(0, frameEndIndex);

      if (rawFrame.isEmpty) continue;

      // First byte is the KISS command
      int command = rawFrame[0] & 0x0F;
      // We only care about data frames (command 0x00)
      if (command == 0x00) {
        Uint8List ax25Frame = _unescapeKISS(rawFrame.sublist(1));
        AprsPacket? packet = AprsParser.parse(ax25Frame);
        if (packet != null) {
          _packetLogController.add(packet);
        }
      }
    }
  }

  /// Un-escapes special characters in a KISS frame.
  Uint8List _unescapeKISS(Uint8List frame) {
    List<int> unescaped = [];
    for (int i = 0; i < frame.length; i++) {
      if (frame[i] == FESC) {
        i++; // Move to the next byte
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

  /// Disposes of the service, closing all streams.
  void dispose() {
    _systemLogController.close();
    _packetLogController.close();
    _connectionStatusController.close();
    _deviceListController.close();
    _isScanningController.close();
    disconnect();
  }
}