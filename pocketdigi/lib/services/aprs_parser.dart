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

  /// Helper to create an address from a string like "N0CALL-1*"
  factory Ax25Address.fromString(String address) {
    bool digipeated = address.endsWith('*');
    if (digipeated) {
      address = address.substring(0, address.length - 1);
    }

    if (address.contains('-')) {
      var parts = address.split('-');
      return Ax25Address(
        callsign: parts[0].toUpperCase(),
        ssid: int.tryParse(parts[1]) ?? 0,
        hasBeenDigipeated: digipeated,
      );
    } else {
      return Ax25Address(
        callsign: address.toUpperCase(),
        ssid: 0,
        hasBeenDigipeated: digipeated,
      );
    }
  }

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
  final Uint8List? originalFrame; // Nullable, as IS packets won't have one

  AprsPacket({
    required this.source,
    required this.destination,
    required this.path,
    required this.payload,
    this.originalFrame,
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
        if ((frame[i + 6] & 0x01) == 0x01) {
          pathEndIndex = i + 7;
          break;
        }
      }

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

    frame.addAll(_encodeAddress(packet.destination));
    frame.addAll(_encodeAddress(packet.source));

    for (int i = 0; i < packet.path.length; i++) {
      bool isLast = i == packet.path.length - 1;
      frame.addAll(_encodeAddress(packet.path[i], lastAddress: isLast));
    }

    frame.add(0x03); // Control
    frame.add(0xF0); // PID

    frame.addAll(utf8.encode(packet.payload));

    return Uint8List.fromList(frame);
  }

  /// Encodes a callsign-SSID string into a 7-byte AX.25 address field.
  static Uint8List _encodeAddress(Ax25Address address, {bool lastAddress = false}) {
    Uint8List bytes = Uint8List(7);
    String call = address.callsign.toUpperCase().padRight(6, ' ');

    for (int i = 0; i < 6; i++) {
      bytes[i] = ascii.encode(call[i])[0] << 1;
    }

    int ssidByte = 0;
    ssidByte |= (address.ssid & 0x0F) << 1;
    ssidByte |= (address.hasBeenDigipeated ? 0x80 : 0x00);
    ssidByte |= 0x60; // Reserved bits
    if (lastAddress) {
      ssidByte |= 0x01;
    }
    bytes[6] = ssidByte;

    return bytes;
  }

  /// Parses an APRS packet string (from iGate) into an AprsPacket object.
  static AprsPacket? parseFromString(String aprsString) {
    try {
      if (aprsString.startsWith('#') || aprsString.isEmpty) return null;

      int payloadMarker = aprsString.indexOf(':');
      if (payloadMarker == -1) return null;

      String header = aprsString.substring(0, payloadMarker);
      String payload = aprsString.substring(payloadMarker + 1);

      int destMarker = header.indexOf('>');
      if (destMarker == -1) return null;

      Ax25Address source = Ax25Address.fromString(header.substring(0, destMarker));
      String remainingHeader = header.substring(destMarker + 1);

      List<String> pathParts = remainingHeader.split(',');
      Ax25Address destination = Ax25Address.fromString(pathParts.removeAt(0));
      List<Ax25Address> path =
          pathParts.map((p) => Ax25Address.fromString(p)).toList();

      return AprsPacket(
        source: source,
        destination: destination,
        path: path,
        payload: payload,
      );
    } catch (e) {
      return null;
    }
  }

  /// Creates a new position packet for beaconing.
  static AprsPacket createPositionPacket({
    required String callsignSsid,
    required String dest,
    required List<String> path,
    required double latitude,
    required double longitude,
    required String comment,
  }) {
    String lat = _formatLatitude(latitude);
    String lon = _formatLongitude(longitude);

    // 'I' is the symbol table ID (overlay)
    // '#' is the symbol code (Digi, from the alternate table)
    // Use ${lon} to separate the variable from the 'I#' string
    String payload = '!$lat/${lon}I#$comment'; // <-- BUG FIX HERE

    return AprsPacket(
      source: Ax25Address.fromString(callsignSsid),
      destination: Ax25Address.fromString(dest),
      path: path.map((p) => Ax25Address.fromString(p)).toList(),
      payload: payload,
    );
  }

  /// Formats latitude for APRS packet.
  static String _formatLatitude(double latitude) {
    String hemisphere = latitude >= 0 ? 'N' : 'S';
    latitude = latitude.abs();
    double deg = latitude.floorToDouble();
    double min = (latitude - deg) * 60;
    return '${deg.toInt().toString().padLeft(2, '0')}${min.toStringAsFixed(2).padLeft(5, '0')}$hemisphere';
  }

  /// Formats longitude for APRS packet.
  static String _formatLongitude(double longitude) {
    String hemisphere = longitude >= 0 ? 'E' : 'W';
    longitude = longitude.abs();
    double deg = longitude.floorToDouble();
    double min = (longitude - deg) * 60;
    return '${deg.toInt().toString().padLeft(3, '0')}${min.toStringAsFixed(2).padLeft(5, '0')}$hemisphere';
  }
}