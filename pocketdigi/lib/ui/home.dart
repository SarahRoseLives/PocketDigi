// File: ui/home.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/tnc_service.dart';
import '../services/aprs_is_service.dart';
import '../services/aprs_parser.dart';

// --- Log Entry Data Structure for UI ---
enum UILogEntryType { system, rxPacket, txPacket }

class UILogEntry {
  final String content;
  final UILogEntryType type;
  final PacketSource? txSource; // For coloring TX packets
  final String timestamp;

  UILogEntry({
    required this.content,
    required this.type,
    this.txSource,
  }) : timestamp = DateTime.now().toIso8601String().substring(11, 23);
}
// --- End Log Entry ---

class PocketDigiHomePage extends StatefulWidget {
  const PocketDigiHomePage({super.key});

  @override
  State<PocketDigiHomePage> createState() => _PocketDigiHomePageState();
}

class _PocketDigiHomePageState extends State<PocketDigiHomePage> {
  final TncService _tncService = TncService();
  final AprsIsService _aprsIsService = AprsIsService();
  BluetoothDevice? _selectedDevice;

  // UI-specific state
  final List<UILogEntry> _logs = [];
  final _logScrollController = ScrollController();
  final _callsignController = TextEditingController();
  bool _isDigipeaterEnabled = true;
  bool _isIGateEnabled = false;
  int _packetsHeard = 0;
  int _packetsDigipeated = 0;
  int _packetsGated = 0;
  int _packetsBeaconed = 0;
  Timer? _beaconTimer;
  Position? _currentPosition; // Store current location

  final List<StreamSubscription> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _subscriptions.add(_tncService.systemLogs.listen(_addSystemLog));
    _subscriptions.add(_tncService.rxPacketLogs.listen(_onRxPacket));
    _subscriptions.add(_tncService.txPacketLogs.listen(_onTxPacket));
    _subscriptions.add(_aprsIsService.systemLogs.listen(_addSystemLog));
    _subscriptions.add(_aprsIsService.incomingPackets.listen(_onIsPacket));

    _subscriptions.add(
      _tncService.initialCallsign.listen((callsign) {
        if (mounted) {
          _callsignController.text = callsign;
          _tncService.setDigipeaterEnabled(_isDigipeaterEnabled);
        }
      }),
    );

    _tncService.getPairedDevices();
    _initLocation(); // Get location on startup
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    _beaconTimer?.cancel();
    _tncService.dispose();
    _aprsIsService.dispose();
    _logScrollController.dispose();
    _callsignController.dispose();
    super.dispose();
  }

  // --- Location & Beacon Logic ---
  Future<void> _initLocation() async {
    var status = await Permission.location.request();
    if (!status.isGranted) {
       _addSystemLog('Location permission denied.');
       return;
    }

    _addSystemLog('Location permission granted. Getting position...');
    try {
      // Get an initial position
      _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);
      _addSystemLog('Initial position acquired: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');

      // Also start listening for location changes
      Geolocator.getPositionStream().listen((Position position) {
        _currentPosition = position;
      });

    } catch (e) {
       _addSystemLog('Could not get initial position: $e');
    }
  }

  void _startBeacons() {
    _beaconTimer?.cancel();
    _beaconTimer = Timer.periodic(const Duration(minutes: 10), (timer) {
      _sendBeacon();
    });
    // Send one beacon immediately
    _sendBeacon();
  }

  Future<void> _sendBeacon() async {
    if (_callsignController.text.isEmpty) return;
    if (_currentPosition == null) {
      _addSystemLog('Cannot send beacon: No location data.');
      return;
    }

    try {
      AprsPacket beacon = AprsParser.createPositionPacket(
        callsignSsid: _callsignController.text,
        dest: 'APRS',
        path: ['WIDE1-1', 'WIDE2-1'],
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        comment: 'PocketDigi v1.0',
      );

      // Send to RF
      _tncService.transmitPacket(beacon, source: PacketSource.beacon);
      // Send to IS (if connected)
      if(_isIGateEnabled) {
        _aprsIsService.sendPacket(beacon.toString());
      }

    } catch (e) {
      _addSystemLog('Error creating beacon: $e');
    }
  }

  // --- Stream Listeners ---
  void _addSystemLog(String message) {
    _updateLogs(UILogEntry(content: message, type: UILogEntryType.system));
  }

  /// Handles a packet received from RF (TNC)
  void _onRxPacket(AprsPacket packet) {
    setState(() => _packetsHeard++);
    _updateLogs(UILogEntry(content: packet.toString(), type: UILogEntryType.rxPacket));

    // RF-to-IS: Gate the packet to the internet if iGate is on
    if (_isIGateEnabled) {
      // CRITICAL: Prevent IS-to-IS loops. Do not gate packets that originated from IS.
      // These are typically identified by a "qAR" or "qAO" in the path.
      bool fromIS = packet.path.any((hop) => hop.callsign.startsWith('qA'));
      if (!fromIS) {
        _aprsIsService.sendPacket(packet.toString());
      }
    }
  }

  /// Handles a packet received from IS (Internet)
  void _onIsPacket(String packetString) {
    // IS-to-RF: Gate the packet to the radio
    AprsPacket? packet = AprsParser.parseFromString(packetString);
    if (packet != null) {
      // Prevent gating our own beacons back to RF
      if (packet.source.callsign == _callsignController.text.split('-')[0]) {
        return;
      }
      _tncService.transmitPacket(packet, source: PacketSource.iGate);
    }
  }

  /// Handles logging for *any* transmitted packet
  void _onTxPacket(TransmittedPacket tx) {
    setState(() {
      switch (tx.source) {
        case PacketSource.digipeat:
          _packetsDigipeated++;
          break;
        case PacketSource.iGate:
          _packetsGated++;
          break;
        case PacketSource.beacon:
          _packetsBeaconed++;
          break;
      }
    });
    _updateLogs(UILogEntry(
      content: tx.packet.toString(),
      type: UILogEntryType.txPacket,
      txSource: tx.source,
    ));
  }

  void _updateLogs(UILogEntry entry) {
    if (!mounted) return;
    setState(() {
      _logs.add(entry);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // --- UI Event Handlers ---
  void _onToggleIGate(bool value) async {
    setState(() => _isIGateEnabled = value);
    if (value) {
      if (_callsignController.text.isEmpty) {
        _addSystemLog('Error: Set callsign before enabling iGate.');
        setState(() => _isIGateEnabled = false);
        return;
      }

      if (_currentPosition == null) {
         _addSystemLog('Error: No location. Trying to get one...');
         await _initLocation(); // Try again to get location
         if (_currentPosition == null) {
           _addSystemLog('Error: Cannot enable iGate without location.');
           setState(() => _isIGateEnabled = false);
           return;
         }
      }

      // Now we connect with a valid location
      _aprsIsService.connect(
        callsign: _callsignController.text,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
      );
    } else {
      _aprsIsService.disconnect();
    }
  }

  void _onToggleConnection(bool isConnected) {
    if (isConnected) {
      _tncService.disconnect();
      _beaconTimer?.cancel();
    } else {
      if (_selectedDevice == null) return;
      _tncService.connect(_selectedDevice!);
      _startBeacons(); // Start beacons once connected to TNC
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PocketDigi'),
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildConnectionCard(),
            const SizedBox(height: 16),
            _buildConfigurationCard(),
            const SizedBox(height: 16),
            _buildStatisticsCard(),
            const SizedBox(height: 16),
            _buildLogCard(),
          ],
        ),
      ),
    );
  }

  // --- UI Builder Methods ---
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: Colors.blueAccent)),
    );
  }

  Widget _buildConnectionCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: StreamBuilder<bool>(
            stream: _tncService.isConnectedStream,
            initialData: false,
            builder: (context, snapshot) {
              final isConnected = snapshot.data ?? false;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Bluetooth TNC'),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12.0),
                          decoration: BoxDecoration(
                              color: Colors.grey[800],
                              borderRadius: BorderRadius.circular(8.0)),
                          child: StreamBuilder<List<BluetoothDevice>>(
                            stream: _tncService.deviceStream,
                            initialData: const [],
                            builder: (context, snapshot) {
                              return DropdownButtonHideUnderline(
                                child: DropdownButton<BluetoothDevice>(
                                  value: _selectedDevice,
                                  isExpanded: true,
                                  hint: const Text('Select a Paired TNC'),
                                  dropdownColor: Colors.grey[850],
                                  items: snapshot.data?.map((device) {
                                    return DropdownMenuItem(
                                      value: device,
                                      child:
                                          Text(device.name ?? device.address),
                                    );
                                  }).toList(),
                                  onChanged: isConnected
                                      ? null
                                      : (device) => setState(
                                          () => _selectedDevice = device),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      StreamBuilder<bool>(
                        stream: _tncService.isScanningStream,
                        initialData: true,
                        builder: (context, snapshot) {
                          final isScanning = snapshot.data ?? false;
                          return isScanning
                              ? const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: CircularProgressIndicator()))
                              : IconButton(
                                  icon: const Icon(Icons.refresh),
                                  onPressed: isConnected
                                      ? null
                                      : _tncService.getPairedDevices,
                                  tooltip: 'Scan for Paired Devices',
                                );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                  color: isConnected
                                      ? Colors.greenAccent.shade400
                                      : Colors.redAccent.shade400,
                                  shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Text(isConnected ? 'Connected' : 'Disconnected',
                              style: TextStyle(
                                  color: isConnected
                                      ? Colors.greenAccent.shade400
                                      : Colors.redAccent.shade400,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      ElevatedButton.icon(
                        onPressed: (_selectedDevice == null && !isConnected)
                            ? null
                            : () => _onToggleConnection(isConnected),
                        icon: Icon(isConnected
                            ? Icons.bluetooth_disabled
                            : Icons.bluetooth_connected),
                        label: Text(isConnected ? 'Disconnect' : 'Connect'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isConnected
                              ? Colors.redAccent.shade400
                              : Colors.blueAccent.shade400,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8.0)),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            }),
      ),
    );
  }

  Widget _buildConfigurationCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: StreamBuilder<bool>(
            stream: _tncService.isConnectedStream,
            initialData: false,
            builder: (context, snapshot) {
              final isConnected = snapshot.data ?? false;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Operation'),
                  TextField(
                    controller: _callsignController,
                    decoration:
                        const InputDecoration(labelText: 'Callsign-SSID'),
                    enabled: !isConnected && !_isIGateEnabled,
                    onChanged: (value) => _tncService.setCallsign(value),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Enable Digipeater'),
                    value: _isDigipeaterEnabled,
                    onChanged: (bool value) {
                      setState(() => _isDigipeaterEnabled = value);
                      _tncService.setDigipeaterEnabled(value);
                    },
                    activeColor: Colors.blueAccent,
                  ),
                  SwitchListTile(
                    title: const Text('Enable iGate'),
                    value: _isIGateEnabled,
                    // You can't toggle iGate while connected to the TNC
                    // to prevent callsign/filter mismatches.
                    onChanged: isConnected ? null : _onToggleIGate,
                    activeColor: Colors.blueAccent,
                  ),
                ],
              );
            }),
      ),
    );
  }

  Widget _buildStatisticsCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Statistics'),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Heard', _packetsHeard.toString()),
                _buildStatItem('Digipeated', _packetsDigipeated.toString()),
                _buildStatItem('Gated', _packetsGated.toString()),
                _buildStatItem('Beaconed', _packetsBeaconed.toString()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }

  Widget _buildLogCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Activity Log'),
            Container(
              height: 200,
              decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8.0)),
              padding: const EdgeInsets.all(8.0),
              child: ListView.builder(
                controller: _logScrollController,
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  final log = _logs[index];
                  Color textColor = Colors.white70; // System
                  String prefix = '';

                  switch (log.type) {
                    case UILogEntryType.rxPacket:
                      textColor = Colors.lightGreenAccent.shade400;
                      prefix = 'RX: ';
                      break;
                    case UILogEntryType.txPacket:
                      prefix = 'TX: ';
                      switch (log.txSource) {
                        case PacketSource.digipeat:
                          textColor = Colors.yellowAccent.shade400; // Digi
                          break;
                        case PacketSource.iGate:
                          textColor = Colors.cyanAccent; // Gated to RF
                          break;
                        case PacketSource.beacon:
                          textColor = Colors.orangeAccent; // Our beacon
                          break;
                        default:
                          textColor = Colors.yellow;
                      }
                      break;
                    case UILogEntryType.system:
                      textColor = Colors.white70;
                      break;
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12),
                        children: [
                          TextSpan(
                            text: '[${log.timestamp}] ',
                            style: const TextStyle(color: Colors.white38),
                          ),
                          TextSpan(
                            text: '$prefix${log.content}',
                            style: TextStyle(color: textColor),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}