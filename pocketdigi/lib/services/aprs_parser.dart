// File: services/aprs_parser.dart

import 'dart:convert';
import 'dart:typed_data';

/// Represents a 7-byte AX.25 address field.
class Ax25Address {
  String callsign;
  int ssid;
  bool hasBeenDigipeated; // The "H-bit" or "used" bit

  Ax25Address({
    required this.callsign,
    this.ssid = 0,
    this.hasBeenDigipeated = false,
  });

  /// Returns the standard string representation (e.g., "N0CALL-1*")
  @override
  String toString() {
    String callSsid = ssid > 0 ? '$callsign-$ssid' : callsign;
    return hasBeenDigipeated ? '$callSsid*' : callSsid;
  }

  /// Checks if this address matches a generic path (e.g., "WIDE1-1")
  bool matches(String genericPath) {
    if (genericPath.contains('-')) {
      var parts = genericPath.split('-');
      return callsign.toUpperCase() == parts[0].toUpperCase() &&
          ssid == int.tryParse(parts[1]);
    } else {
      return callsign.toUpperCase() == genericPath.toUpperCase() && ssid == 0;
    }
  }
}

/// Represents a successfully parsed APRS packet.
class AprsPacket {
  final Ax25Address source;
  final Ax25Address destination;
  final List<Ax25Address> path;
  final String payload;
  final Uint8List originalFrame; // Keep original for debugging or forwarding

  AprsPacket({
    required this.source,
    required this.destination,
    required this.path,
    required this.payload,
    required this.originalFrame,
  });

  /// Provides a human-readable representation of the packet.
  @override
  String toString() {
    String pathString = path.map((p) => p.toString()).join(',');
    return '$source>$destination,$pathString:$payload';
  }
}

/// A utility class for parsing AND encoding raw AX.25 frames.
class AprsParser {
  /// Parses a raw AX.25 byte frame into an APRS packet.
  static AprsPacket? parse(Uint8List frame) {
    if (frame.length < 16) return null;

    try {
      Ax25Address destination = _parseAddress(frame.sublist(0, 7));
      Ax25Address source = _parseAddress(frame.sublist(7, 14));

      List<Ax25Address> path = [];
      int pathEndIndex = 14;

      for (int i = 14; i < frame.length - 7; i += 7) {
        path.add(_parseAddress(frame.sublist(i, i + 7)));
        // The last address byte has its least significant bit set to 1
        if ((frame[i + 6] & 0x01) == 0x01) {
          pathEndIndex = i + 7;
          break;
        }
      }

      // Check for Control (0x03) and PID (0xF0)
      if (pathEndIndex + 2 > frame.length ||
          frame[pathEndIndex] != 0x03 ||
          frame[pathEndIndex + 1] != 0xF0) {
        return null; // Not a UI frame
      }

      String payload =
          utf8.decode(frame.sublist(pathEndIndex + 2), allowMalformed: true);

      return AprsPacket(
        source: source,
        destination: destination,
        path: path,
        payload: payload.trim(),
        originalFrame: frame,
      );
    } catch (e) {
      return null;
    }
  }

  /// Decodes a 7-byte AX.25 address field.
  static Ax25Address _parseAddress(Uint8List addressBytes) {
    String callsign =
        ascii.decode(addressBytes.sublist(0, 6).map((b) => b >> 1).toList()).trim();
    int ssid = (addressBytes[6] >> 1) & 0x0F;
    bool hasBeenDigipeated = (addressBytes[6] & 0x80) == 0x80;

    return Ax25Address(
      callsign: callsign,
      ssid: ssid,
      hasBeenDigipeated: hasBeenDigipeated,
    );
  }

  /// Encodes an AprsPacket back into a raw AX.25 frame.
  static Uint8List encode(AprsPacket packet) {
    List<int> frame = [];

    // Add addresses
    frame.addAll(_encodeAddress(packet.destination));
    frame.addAll(_encodeAddress(packet.source));

    for (int i = 0; i < packet.path.length; i++) {
      bool isLast = i == packet.path.length - 1;
      frame.addAll(_encodeAddress(packet.path[i], lastAddress: isLast));
    }

    // Add Control (0x03) and PID (0xF0)
    frame.add(0x03);
    frame.add(0xF0);

    // Add Payload
    frame.addAll(utf8.encode(packet.payload));

    return Uint8List.fromList(frame);
  }

  /// Encodes a callsign-SSID string into a 7-byte AX.25 address field.
  static Uint8List _encodeAddress(Ax25Address address, {bool lastAddress = false}) {
    Uint8List bytes = Uint8List(7);
    String call = address.callsign.toUpperCase().padRight(6, ' ');

    // Encode 6-char callsign, shifted left by 1 bit
    for (int i = 0; i < 6; i++) {
      bytes[i] = ascii.encode(call[i])[0] << 1;
    }

    // Encode SSID byte
    int ssidByte = 0;
    ssidByte |= (address.ssid & 0x0F) << 1; // SSID
    ssidByte |= (address.hasBeenDigipeated ? 0x80 : 0x00); // H-bit
    ssidByte |= 0x60; // Reserved bits, standard for UI frames
    if (lastAddress) {
      ssidByte |= 0x01; // End of address list bit
    }
    bytes[6] = ssidByte;

    return bytes;
  }
}