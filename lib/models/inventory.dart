import 'package:equatable/equatable.dart';
import 'enums.dart';
import 'medicine.dart';
import 'medicine_variant.dart';
import '../core/utils/stock_freshness.dart';

/// Ligne de stock pharmacie (PharmacyInventory).
/// Sépare clairement le médicament global de la quantité / prix locaux.
class Inventory extends Equatable {
  final String? id;
  final String pharmacyId;
  final String medicineId;
  final String? medicineVariantId;
  final StockStatus status;
  final int? quantity;
  final int reservedQuantity;
  final int? lastUpdatedSeconds;
  final DateTime? lastUpdatedAt;
  final Medicine? medicine;
  final MedicineVariant? variant;
  /// Prix unitaire en FCFA chez cette pharmacie.
  final int? unitPriceXaf;
  final StockSource stockSource;
  final DateTime? lastSyncedAt;
  final int lowStockThreshold;
  final String? externalRef;

  const Inventory({
    this.id,
    required this.pharmacyId,
    required this.medicineId,
    this.medicineVariantId,
    required this.status,
    this.quantity,
    this.reservedQuantity = 0,
    this.lastUpdatedSeconds,
    this.lastUpdatedAt,
    this.medicine,
    this.variant,
    this.unitPriceXaf,
    this.stockSource = StockSource.manual,
    this.lastSyncedAt,
    this.lowStockThreshold = 5,
    this.externalRef,
  });

  DateTime? get lastUpdated {
    if (lastUpdatedAt != null) return lastUpdatedAt;
    if (lastUpdatedSeconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(lastUpdatedSeconds! * 1000);
  }

  /// Quantité réellement réservable (jamais pour UNKNOWN).
  int get availableQuantity {
    if (status == StockStatus.unknown) return 0;
    return ((quantity ?? 0) - reservedQuantity).clamp(0, 1 << 30);
  }

  /// Affichage quantité : null si UNKNOWN (ne pas mentir sur la dispo).
  int? get displayQuantity =>
      status == StockStatus.unknown ? null : availableQuantity;

  bool get isOrderable => status.isOrderable && availableQuantity > 0;

  bool get isStale => StockFreshness.isStale(
        lastUpdated,
        source: stockSource,
        lastSyncedAt: lastSyncedAt,
      );

  String get freshnessLabel => StockFreshness.label(
        status: status,
        lastUpdated: lastUpdated,
      );

  factory Inventory.fromJson(Map<String, dynamic> json) {
    final statusStr = json['stock_status'] as String? ??
        json['availability'] as String? ??
        json['status'] as String? ??
        'unknown';
    final status = parseStockStatus(statusStr);

    DateTime? parsedUpdated;
    final rawUpdated = json['last_updated'] ?? json['updated_at'];
    if (rawUpdated is String) {
      parsedUpdated = DateTime.tryParse(rawUpdated);
    } else if (rawUpdated is num) {
      // epoch seconds
      parsedUpdated =
          DateTime.fromMillisecondsSinceEpoch(rawUpdated.toInt() * 1000);
    }

    DateTime? parsedSynced;
    final rawSynced = json['last_synced_at'];
    if (rawSynced is String) {
      parsedSynced = DateTime.tryParse(rawSynced);
    }

    return Inventory(
      id: json['id']?.toString(),
      pharmacyId: json['pharmacy_id'] as String? ?? '',
      medicineId: json['medicine_id'] as String? ??
          json['drug_id'] as String? ??
          '',
      medicineVariantId: json['medicine_variant_id']?.toString(),
      status: status,
      quantity: (json['quantity'] as num?)?.toInt(),
      reservedQuantity: (json['reserved_quantity'] as num?)?.toInt() ?? 0,
      lastUpdatedSeconds: parsedUpdated != null
          ? parsedUpdated.millisecondsSinceEpoch ~/ 1000
          : (json['last_updated'] is num
              ? (json['last_updated'] as num).toInt()
              : null),
      lastUpdatedAt: parsedUpdated,
      medicine: json['medicine'] != null
          ? Medicine.fromJson(json['medicine'] as Map<String, dynamic>)
          : (json['medicines'] != null
              ? Medicine.fromJson(
                  Map<String, dynamic>.from(json['medicines'] as Map),
                )
              : null),
      variant: json['medicine_variants'] != null
          ? MedicineVariant.fromJson(
              Map<String, dynamic>.from(json['medicine_variants'] as Map),
            )
          : null,
      unitPriceXaf: (json['unit_price_xaf'] as num?)?.toInt() ??
          (json['price'] as num?)?.toInt() ??
          (json['price_xaf'] as num?)?.toInt(),
      stockSource: StockSourceX.fromString(json['stock_source']?.toString()),
      lastSyncedAt: parsedSynced,
      lowStockThreshold: (json['low_stock_threshold'] as num?)?.toInt() ?? 5,
      externalRef: json['external_ref']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'pharmacy_id': pharmacyId,
        'medicine_id': medicineId,
        'medicine_variant_id': medicineVariantId,
        'stock_status': status.dbValue,
        'status': status.dbValue,
        'quantity': quantity,
        'reserved_quantity': reservedQuantity,
        'last_updated': lastUpdatedSeconds,
        'unit_price_xaf': unitPriceXaf,
        'stock_source': stockSource.dbValue,
        'low_stock_threshold': lowStockThreshold,
        'external_ref': externalRef,
      };

  @override
  List<Object?> get props => [
        id,
        pharmacyId,
        medicineId,
        medicineVariantId,
        status,
        quantity,
        reservedQuantity,
        unitPriceXaf,
        stockSource,
      ];
}

StockStatus parseStockStatus(String? statusStr) {
  switch ((statusStr ?? 'unknown').toLowerCase().replaceAll('-', '_')) {
    case 'available':
    case 'in_stock':
      return StockStatus.available;
    case 'low_stock':
    case 'low':
      return StockStatus.lowStock;
    case 'out_of_stock':
    case 'unavailable':
      return StockStatus.outOfStock;
    default:
      return StockStatus.unknown;
  }
}
