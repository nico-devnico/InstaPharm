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
    return Pharmacy(
      id: json['id'] as String? ?? json['uuid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? json['photo_url'] as String?,
      address: json['address'] as String?,
      city: json['city'] as String?,
      postalCode: json['postal_code'] as String? ?? json['zip_code'] as String?,
      coordinates: json['coordinates'] != null
          ? Coordinates.fromJson(
              json['coordinates'] as Map<String, dynamic>)
          : (json['latitude'] != null && json['longitude'] != null
              ? Coordinates(
                  latitude: (json['latitude'] as num).toDouble(),
                  longitude: (json['longitude'] as num).toDouble(),
                )
              : null),
      phone: json['phone'] as String? ?? json['phone_number'] as String?,
      email: json['email'] as String?,
      website: json['website'] as String?,
      openingHours: (json['opening_hours'] as List<dynamic>?)
          ?.map((e) => OpeningHour.fromJson(e as Map<String, dynamic>))
          .toList(),
      rating: (json['rating'] as num?)?.toDouble(),
      reviewCount: json['review_count'] as int? ?? json['reviews_count'] as int?,
      isDuty: (json['is_duty'] as bool?) ?? json['duty'] as bool? ?? false,
      isOpen: (json['is_open'] as bool?) ?? json['open'] as bool?,
      distanceMeters: (json['distance_meters'] as num?)?.toDouble() ??
          (json['distance'] as num?)?.toDouble(),
      travelTimeSeconds: (json['travel_time_seconds'] as int?) ??
          (json['travel_time'] as int?),
      services: (json['services'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      isVerified: (json['is_verified'] as bool?) ??
          json['verified'] as bool? ??
          false,
      isPlatform: json['is_platform'] as bool? ?? false,
      ownerUserId: json['owner_user_id']?.toString(),
    );
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
