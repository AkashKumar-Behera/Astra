import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ReverseGeocodingService {
  static final Map<String, String> _cache = {};

  /// Resolves human-readable address from GPS coordinates (e.g. "Uttara, Bhubaneswar")
  static Future<String> getAddressFromCoordinates(double lat, double lng) async {
    final key = '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=$lat&lon=$lng&format=json&zoom=14&addressdetails=1',
      );

      final res = await http.get(
        uri,
        headers: {
          'User-Agent': 'Astra-Cosmic-App/1.0',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;

        if (address != null) {
          final suburb = address['suburb'] ??
              address['neighbourhood'] ??
              address['village'] ??
              address['road'] ??
              '';
          final city = address['city'] ??
              address['town'] ??
              address['state_district'] ??
              address['county'] ??
              '';
          final state = address['state'] ?? '';

          String resolved = '';
          if (suburb.isNotEmpty && city.isNotEmpty) {
            resolved = '$suburb, $city';
          } else if (city.isNotEmpty && state.isNotEmpty) {
            resolved = '$city, $state';
          } else if (city.isNotEmpty) {
            resolved = city;
          } else if (data['display_name'] != null) {
            final parts = (data['display_name'] as String).split(',');
            resolved = parts.take(2).join(',').trim();
          }

          if (resolved.isNotEmpty) {
            _cache[key] = resolved;
            return resolved;
          }
        }
      }
    } catch (e) {
      debugPrint('[ReverseGeocodingService] Error: $e');
    }

    final fallback = 'Locality (${lat.toStringAsFixed(2)}°, ${lng.toStringAsFixed(2)}°)';
    _cache[key] = fallback;
    return fallback;
  }
}
