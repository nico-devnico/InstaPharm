import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/coordinates.dart';

class GeocodeResult {
  final String displayName;
  final String? road;
  final String? neighbourhood;
  final String? suburb;
  final String? city;
  final String? country;
  final Coordinates coordinates;

  const GeocodeResult({
    required this.displayName,
    required this.coordinates,
    this.road,
    this.neighbourhood,
    this.suburb,
    this.city,
    this.country,
  });

  String get shortAddress {
    final parts = <String>[];
    if (road != null && road!.isNotEmpty) parts.add(road!);
    if (neighbourhood != null && neighbourhood!.isNotEmpty) {
      parts.add(neighbourhood!);
    } else if (suburb != null && suburb!.isNotEmpty) {
      parts.add(suburb!);
    }
    if (city != null && city!.isNotEmpty) parts.add(city!);
    return parts.isEmpty ? displayName : parts.join(', ');
  }
}

/// Géocodage réel via Nominatim (OpenStreetMap).
class GeocodingService {
  GeocodingService._();
  static final GeocodingService instance = GeocodingService._();

  static const _base = 'https://nominatim.openstreetmap.org';

  Future<GeocodeResult?> reverseGeocode({
    required double latitude,
    required double longitude,
  }) async {
    final uri = Uri.parse(
      '$_base/reverse?format=jsonv2&lat=$latitude&lon=$longitude'
      '&addressdetails=1&accept-language=fr',
    );

    try {
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'InstaPharm/1.0 (Cameroon pharmacy app)',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final address = data['address'] as Map<String, dynamic>? ?? {};

      return GeocodeResult(
        displayName: data['display_name']?.toString() ?? '',
        coordinates: Coordinates(latitude: latitude, longitude: longitude),
        road: address['road']?.toString() ??
            address['pedestrian']?.toString() ??
            address['path']?.toString(),
        neighbourhood: address['neighbourhood']?.toString() ??
            address['quarter']?.toString() ??
            address['residential']?.toString(),
        suburb: address['suburb']?.toString() ??
            address['city_district']?.toString(),
        city: address['city']?.toString() ??
            address['town']?.toString() ??
            address['village']?.toString() ??
            address['municipality']?.toString(),
        country: address['country']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }
}
