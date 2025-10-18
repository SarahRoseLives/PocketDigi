// File: services/aprs_parser.dart

import 'dart:convert';
import 'dart:typed_data';

/// Represents a successfully parsed APRS packet.
class AprsPacket {
  final String source;
  final String destination;
  final List<String> path;
  final String payload;

  AprsPacket({
    required this.source,
    required this.destination,
    required this.path,
    required this.payload,
  });

  /// Provides a human-readable representation of the packet.
  @override
  String toString() {
    String pathString = path.join(',');
    return '$source>$destination,$pathString:$payload';
  }
}

/// A utility class for parsing raw AX.25 frames into APRS packets.
class AprsParser {
  /// Parses a raw AX.25 byte frame (the payload of a KISS data frame).
  /// Returns an [AprsPacket] on success, or null on failure.
  static AprsPacket? parse(Uint8List frame) {
    if (frame.length < 16) {
      // Minimum length for dest, src, and control fields
      return null;
    }

    try {
      // AX.25 addresses are 7 bytes each: 6 for callsign, 1 for SSID
      String destination = _parseAddress(frame.sublist(0, 7));
      String source = _parseAddress(frame.sublist(7, 14));

      List<String> path = [];
      int pathEndIndex = 14;

      // Loop through path digipeaters until we find the end of the address field
      for (int i = 14; i < frame.length - 7; i += 7) {
        // The last address byte has its least significant bit set to 1
        if ((frame[i + 6] & 0x01) == 0x01) {
          path.add(_parseAddress(frame.sublist(i, i + 7)));
          pathEndIndex = i + 7;
          break;
        } else {
          path.add(_parseAddress(frame.sublist(i, i + 7)));
        }
      }

      // Find the payload start, which is after Control (0x03) and PID (0xF0)
      if (pathEndIndex + 2 >= frame.length ||
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
      );
    } catch (e) {
      // Catch any potential range errors or decoding issues
      return null;
    }
  }

  /// Decodes a 7-byte AX.25 address field into a callsign-SSID string.
  static String _parseAddress(Uint8List addressBytes) {
    // Callsigns are stored as 6 ASCII chars, shifted left by 1 bit.
    String callsign =
        ascii.decode(addressBytes.sublist(0, 6).map((b) => b >> 1).toList()).trim();

    // The SSID is encoded in the 7th byte.
    int ssid = (addressBytes[6] >> 1) & 0x0F;

    return ssid > 0 ? '$callsign-$ssid' : callsign;
  }
}