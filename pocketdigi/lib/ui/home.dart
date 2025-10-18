// File: ui/home.dart

import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../services/tnc_service.dart';
import '../services/aprs_parser.dart';

// --- Log Entry Data Structure for UI ---
enum UILogEntryType { system, packet }

class UILogEntry {
  final String content;
  final UILogEntryType type;
  final String timestamp;

  UILogEntry({required this.content, required this.type})
      : timestamp = DateTime.now().toIso8601String().substring(11, 23);
}
// --- End Log Entry ---

class PocketDigiHomePage extends StatefulWidget {
  const PocketDigiHomePage({super.key});

  @override
  State<PocketDigiHomePage> createState() => _PocketDigiHomePageState();
}

class _PocketDigiHomePageState extends State<PocketDigiHomePage> {
  // The UI only needs a reference to the service
  final TncService _tncService = TncService();
  BluetoothDevice? _selectedDevice;

  // UI-specific state
  final List<UILogEntry> _logs = [];
  final _logScrollController = ScrollController();
  final _callsignController = TextEditingController(text: 'N0CALL-1');
  int _packetsHeard = 0;
  int _packetsDigipeated = 0;

  @override
  void initState() {
    super.initState();
    // Listen to the streams from the service to update the UI
    _tncService.systemLogs.listen(_addSystemLog);
    _tncService.packetLogs.listen(_addPacketLog);
    _tncService.getPairedDevices(); // Initial scan
  }

  @override
  void dispose() {
    _tncService.dispose();
    _logScrollController.dispose();
    _callsignController.dispose();
    super.dispose();
  }

  void _addSystemLog(String message) {
    _updateLogs(UILogEntry(content: message, type: UILogEntryType.system));
  }

  void _addPacketLog(AprsPacket packet) {
    setState(() {
      _packetsHeard++;
    });
    _updateLogs(
        UILogEntry(content: packet.toString(), type: UILogEntryType.packet));

    // --- YOUR DIGIPEATER/IGATE LOGIC WILL GO HERE ---
    // if (shouldDigipeat(packet)) {
    //   _tncService.send(modifiedPacket);
    //   setState(() => _packetsDigipeated++);
    // }
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
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(color: Colors.blueAccent),
      ),
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
                            borderRadius: BorderRadius.circular(8.0),
                          ),
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
                                      child: Text(device.name ?? device.address),
                                    );
                                  }).toList(),
                                  onChanged: isConnected
                                      ? null
                                      : (device) =>
                                          setState(() => _selectedDevice = device),
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
                            : () => isConnected
                                ? _tncService.disconnect()
                                : _tncService.connect(_selectedDevice!),
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
                  decoration: const InputDecoration(labelText: 'Callsign-SSID'),
                  enabled: !isConnected
                ),
                const SizedBox(height: 8),
                // In a real app, you would pass these values to the TNC service
                // for it to use in its digipeater logic.
                SwitchListTile(
                  title: const Text('Enable Digipeater'),
                  value: true, // Placeholder
                  onChanged: isConnected ? (bool value) {} : null,
                  activeColor: Colors.blueAccent,
                ),
                SwitchListTile(
                  title: const Text('Enable iGate'),
                  value: false, // Placeholder
                  onChanged: isConnected ? (bool value) {} : null,
                  activeColor: Colors.blueAccent,
                ),
              ],
            );
          }
        ),
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
                _buildStatItem('Gated', "0"), // Placeholder
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
                  Color textColor = Colors.white70;

                  if (log.type == UILogEntryType.packet) {
                    textColor = Colors.lightGreenAccent.shade400;
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                        children: [
                          TextSpan(
                            text: '[${log.timestamp}] ',
                            style: const TextStyle(color: Colors.white38),
                          ),
                          TextSpan(
                            text: log.content,
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