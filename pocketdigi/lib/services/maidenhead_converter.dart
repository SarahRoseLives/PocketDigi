// File: services/maidenhead_converter.dart

class MaidenheadConverter {
  /// Converts a Maidenhead Grid Locator (e.g., "FN31pr" or "FN31") to Lat/Long.
  /// Returns a Map with 'latitude' and 'longitude', or null if invalid.
  static Map<String, double>? gridToLatLong(String grid) {
    grid = grid.trim().toUpperCase();

    if (!RegExp(r'^[A-R]{2}[0-9]{2}([A-X]{2})?$').hasMatch(grid)) {
      return null; // Invalid format
    }

    // Decode Field (First 2 chars) - 20° x 10°
    double lon = (grid.codeUnitAt(0) - 'A'.codeUnitAt(0)) * 20.0 - 180.0;
    double lat = (grid.codeUnitAt(1) - 'A'.codeUnitAt(0)) * 10.0 - 90.0;

    // Decode Square (Next 2 digits) - 2° x 1°
    lon += (grid.codeUnitAt(2) - '0'.codeUnitAt(0)) * 2.0;
    lat += (grid.codeUnitAt(3) - '0'.codeUnitAt(0)) * 1.0;

    // Decode Subsquare (Optional last 2 chars) - 5' x 2.5'
    if (grid.length == 6) {
      lon += (grid.codeUnitAt(4) - 'A'.codeUnitAt(0)) * (5.0 / 60.0);
      lat += (grid.codeUnitAt(5) - 'A'.codeUnitAt(0)) * (2.5 / 60.0);

      // Center of the subsquare
      lon += (2.5 / 60.0);
      lat += (1.25 / 60.0);
    } else {
      // Center of the square (if only 4 chars provided)
      lon += 1.0;
      lat += 0.5;
    }

    return {'latitude': lat, 'longitude': lon};
  }
}