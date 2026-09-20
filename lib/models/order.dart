import 'package:equatable/equatable.dart';
import 'coordinates.dart';
import 'enums.dart';
import 'medicine.dart';
import 'pharmacy.dart';

class OrderItem extends Equatable {
  final String medicineId;
  final String medicineName;
  final String? brand;
  final String? dosage;
  final int quantity;
  final int unitPriceXaf;
  final bool requiresPrescription;

  const OrderItem({
    required this.medicineId,
    required this.medicineName,
    this.brand,
    this.dosage,
    required this.quantity,
    required this.unitPriceXaf,
    this.requiresPrescription = false,
  });

  int get lineTotalXaf => unitPriceXaf * quantity;

  factory OrderItem.fromMedicine(Medicine medicine, {int quantity = 1}) {
    return OrderItem(
      medicineId: medicine.id,
      medicineName: medicine.name,
      brand: medicine.brand,
      dosage: medicine.dosage,
      quantity: quantity,
      unitPriceXaf: medicine.priceXaf ?? 0,
      requiresPrescription: medicine.requiresPrescription ?? false,
    );
  }

  @override
  List<Object?> get props => [medicineId, quantity, unitPriceXaf];
}

class DeliveryInfo extends Equatable {
  final String recipientName;
  final String phone;
  final String city;
  final String neighborhood;
  final String addressDetail;
  final String? courierName;
  final String? courierPhone;
  final Coordinates? courierLocation;
  final Coordinates? destination;
  final List<Coordinates> routeGeometry;
  final double? routeDistanceMeters;
  final int? routeDurationSeconds;
  /// Progression 0→1 le long de l’itinéraire routier.
  final double progress;
  final int estimatedMinutes;
  /// Destination issue du GPS patient (pas un centroïde quartier).
  final bool fromLiveGps;
  /// Instant de départ livreur (pour progression temps réel réelle).
  final DateTime? departedAt;
  /// Dernière ETA OSRM recalculée (secondes restantes).
  final int? liveEtaSeconds;
  final double? liveRemainingMeters;

  const DeliveryInfo({
    required this.recipientName,
    required this.phone,
    required this.city,
    required this.neighborhood,
    required this.addressDetail,
    this.courierName,
    this.courierPhone,
    this.courierLocation,
    this.destination,
    this.routeGeometry = const [],
    this.routeDistanceMeters,
    this.routeDurationSeconds,
    this.progress = 0,
    this.estimatedMinutes = 45,
    this.fromLiveGps = false,
    this.departedAt,
    this.liveEtaSeconds,
    this.liveRemainingMeters,
  });

  String get fullAddress => '$addressDetail, $neighborhood, $city';

  DeliveryInfo copyWith({
    String? courierName,
    String? courierPhone,
    Coordinates? courierLocation,
    Coordinates? destination,
    List<Coordinates>? routeGeometry,
    double? routeDistanceMeters,
    int? routeDurationSeconds,
    double? progress,
    int? estimatedMinutes,
    bool? fromLiveGps,
    DateTime? departedAt,
    int? liveEtaSeconds,
    double? liveRemainingMeters,
  }) {
    return DeliveryInfo(
      recipientName: recipientName,
      phone: phone,
      city: city,
      neighborhood: neighborhood,
      addressDetail: addressDetail,
      courierName: courierName ?? this.courierName,
      courierPhone: courierPhone ?? this.courierPhone,
      courierLocation: courierLocation ?? this.courierLocation,
      destination: destination ?? this.destination,
      routeGeometry: routeGeometry ?? this.routeGeometry,
      routeDistanceMeters: routeDistanceMeters ?? this.routeDistanceMeters,
      routeDurationSeconds: routeDurationSeconds ?? this.routeDurationSeconds,
      progress: progress ?? this.progress,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      fromLiveGps: fromLiveGps ?? this.fromLiveGps,
      departedAt: departedAt ?? this.departedAt,
      liveEtaSeconds: liveEtaSeconds ?? this.liveEtaSeconds,
      liveRemainingMeters: liveRemainingMeters ?? this.liveRemainingMeters,
    );
  }

  @override
  List<Object?> get props => [
        recipientName,
        phone,
        city,
        neighborhood,
        addressDetail,
        courierLocation,
        destination,
        progress,
        estimatedMinutes,
        fromLiveGps,
        departedAt,
        liveEtaSeconds,
      ];
}

class MedicineOrder extends Equatable {
  final String id;
  final String pharmacyId;
  final String pharmacyName;
  final Pharmacy? pharmacy;
  final List<OrderItem> items;
  final FulfillmentType fulfillment;
  final PaymentMethod paymentMethod;
  final OrderStatus status;
  final int subtotalXaf;
  final int deliveryFeeXaf;
  final DeliveryInfo? delivery;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? notes;
  final bool hasPrescription;
  /// UUID Supabase (pour ratings / realtime)
  final String? supabaseId;
  final String? courierName;

  const MedicineOrder({
    required this.id,
    required this.pharmacyId,
    required this.pharmacyName,
    this.pharmacy,
    required this.items,
    required this.fulfillment,
    required this.paymentMethod,
    required this.status,
    required this.subtotalXaf,
    required this.deliveryFeeXaf,
    this.delivery,
    required this.createdAt,
    this.updatedAt,
    this.notes,
    this.hasPrescription = false,
    this.supabaseId,
    this.courierName,
  });

  int get totalXaf => subtotalXaf + deliveryFeeXaf;

  MedicineOrder copyWith({
    OrderStatus? status,
    DeliveryInfo? delivery,
    DateTime? updatedAt,
    String? courierName,
  }) {
    return MedicineOrder(
      id: id,
      pharmacyId: pharmacyId,
      pharmacyName: pharmacyName,
      pharmacy: pharmacy,
      items: items,
      fulfillment: fulfillment,
      paymentMethod: paymentMethod,
      status: status ?? this.status,
      subtotalXaf: subtotalXaf,
      deliveryFeeXaf: deliveryFeeXaf,
      delivery: delivery ?? this.delivery,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: notes,
      hasPrescription: hasPrescription,
      supabaseId: supabaseId,
      courierName: courierName ?? this.courierName,
    );
  }

  @override
  List<Object?> get props => [id, status, totalXaf, createdAt, delivery, supabaseId];
}
