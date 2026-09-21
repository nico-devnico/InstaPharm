import 'package:equatable/equatable.dart';
import 'enums.dart';
import 'opening_hour.dart';
import 'coordinates.dart';

class Pharmacy extends Equatable {
  final String id;
  final String name;
  final String? imageUrl;
  final String? address;
  final String? city;
  final String? postalCode;
  final Coordinates? coordinates;
  final String? phone;
  final String? email;
  final String? website;
  final List<OpeningHour>? openingHours;
  final double? rating;
  final int? reviewCount;
  final bool? isDuty;
  final bool? isOpen;
  final double? distanceMeters;
  final int? travelTimeSeconds;
  final List<String>? services;
  final bool? isVerified;
  /// Pharmacie enregistrée sur la plateforme par l’administrateur.
  final bool isPlatform;
  final String? ownerUserId;

  const Pharmacy({
    required this.id,
    required this.name,
    this.imageUrl,
    this.address,
    this.city,
    this.postalCode,
    this.coordinates,
    this.phone,
    this.email,
    this.website,
    this.openingHours,
    this.rating,
    this.reviewCount,
    this.isDuty,
    this.isOpen,
    this.distanceMeters,
    this.travelTimeSeconds,
    this.services,
    this.isVerified,
    this.isPlatform = false,
    this.ownerUserId,
  });

  String get fullAddress {
    final parts = <String>[];
    if (address != null) parts.add(address!);
    if (postalCode != null) parts.add(postalCode!);
    if (city != null) parts.add(city!);
    return parts.join(' ');
  }

  PharmacyStatus get status {
    if (isDuty == true) return PharmacyStatus.onDuty;
    if (isOpen == true) return PharmacyStatus.open;
    if (isOpen == false) return PharmacyStatus.closed;
    return PharmacyStatus.unknown;
  }

  factory Pharmacy.fromJson(Map<String, dynamic> json) {
    try {
      return Pharmacy(
        id: json['id']?.toString() ?? json['uuid']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        imageUrl:
            json['image_url']?.toString() ?? json['photo_url']?.toString(),
        address: json['address']?.toString(),
        city: json['city']?.toString(),
        postalCode:
            json['postal_code']?.toString() ?? json['zip_code']?.toString(),
        coordinates: Pharmacy._parseCoordinates(json),
        phone: json['phone']?.toString() ?? json['phone_number']?.toString(),
        email: json['email']?.toString(),
        website: json['website']?.toString(),
        openingHours: Pharmacy._parseOpeningHours(json['opening_hours']),
        rating: Pharmacy._asDouble(json['rating']),
        reviewCount: Pharmacy._asInt(json['review_count']) ??
            Pharmacy._asInt(json['reviews_count']),
        isDuty: Pharmacy._asBool(json['is_duty']) ??
            Pharmacy._asBool(json['duty']) ??
            false,
        isOpen: Pharmacy._asBool(json['is_open']) ??
            Pharmacy._asBool(json['open']),
        distanceMeters: Pharmacy._asDouble(json['distance_meters']) ??
            Pharmacy._asDouble(json['distance']),
        travelTimeSeconds: Pharmacy._asInt(json['travel_time_seconds']) ??
            Pharmacy._asInt(json['travel_time']),
        services: Pharmacy._parseServices(json['services']),
        isVerified: Pharmacy._asBool(json['is_verified']) ??
            Pharmacy._asBool(json['verified']) ??
            false,
        isPlatform: Pharmacy._asBool(json['is_platform']) ?? false,
        ownerUserId: json['owner_user_id']?.toString(),
      );
    } catch (_) {
      // Jamais crasher l’UI (page blanche) sur un champ JSON mal typé
      return Pharmacy(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Pharmacie',
        address: json['address']?.toString(),
        city: json['city']?.toString(),
        phone: json['phone']?.toString(),
        isPlatform: Pharmacy._asBool(json['is_platform']) ?? false,
      );
    }
  }

  static Coordinates? _parseCoordinates(Map<String, dynamic> json) {
    final raw = json['coordinates'];
    if (raw is Map) {
      final lat = _asDouble(raw['latitude'] ?? raw['lat']);
      final lng = _asDouble(raw['longitude'] ?? raw['lng'] ?? raw['lon']);
      if (lat != null && lng != null) {
        return Coordinates(latitude: lat, longitude: lng);
      }
    }
    final lat = _asDouble(json['latitude']);
    final lng = _asDouble(json['longitude']);
    if (lat != null && lng != null) {
      return Coordinates(latitude: lat, longitude: lng);
    }
    return null;
  }

  static List<OpeningHour>? _parseOpeningHours(dynamic raw) {
    if (raw == null) return null;
    // jsonb objet / chaîne OSM → ignorer (évite cast crash → page blanche)
    if (raw is! List) return null;
    try {
      return raw
          .whereType<Map>()
          .map((e) => OpeningHour.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static List<String>? _parseServices(dynamic raw) {
    if (raw == null) return null;
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    if (raw is String && raw.trim().isNotEmpty) {
      return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    }
    return null;
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static bool? _asBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'image_url': imageUrl,
        'address': address,
        'city': city,
        'postal_code': postalCode,
        'coordinates': coordinates?.toJson(),
        'phone': phone,
        'email': email,
        'website': website,
        'rating': rating,
        'review_count': reviewCount,
        'is_duty': isDuty,
        'is_open': isOpen,
        'distance_meters': distanceMeters,
        'travel_time_seconds': travelTimeSeconds,
        'services': services,
        'is_platform': isPlatform,
        'owner_user_id': ownerUserId,
      };

  Pharmacy copyWith({
    String? id,
    String? name,
    String? imageUrl,
    String? address,
    String? city,
    String? postalCode,
    Coordinates? coordinates,
    String? phone,
    String? email,
    String? website,
    List<OpeningHour>? openingHours,
    double? rating,
    int? reviewCount,
    bool? isDuty,
    bool? isOpen,
    double? distanceMeters,
    int? travelTimeSeconds,
    List<String>? services,
    bool? isVerified,
    bool? isPlatform,
    String? ownerUserId,
  }) {
    return Pharmacy(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      address: address ?? this.address,
      city: city ?? this.city,
      postalCode: postalCode ?? this.postalCode,
      coordinates: coordinates ?? this.coordinates,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      website: website ?? this.website,
      openingHours: openingHours ?? this.openingHours,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      isDuty: isDuty ?? this.isDuty,
      isOpen: isOpen ?? this.isOpen,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      travelTimeSeconds: travelTimeSeconds ?? this.travelTimeSeconds,
      services: services ?? this.services,
      isVerified: isVerified ?? this.isVerified,
      isPlatform: isPlatform ?? this.isPlatform,
      ownerUserId: ownerUserId ?? this.ownerUserId,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        address,
        city,
        postalCode,
        coordinates,
        isDuty,
        isOpen,
        distanceMeters,
        isPlatform,
      ];
}
