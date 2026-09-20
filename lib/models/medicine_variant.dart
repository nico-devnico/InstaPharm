import 'package:equatable/equatable.dart';

/// Variante d'un médicament (dosage / forme / marque).
/// Hiérarchie : Medicine → MedicineVariant → PharmacyInventory
class MedicineVariant extends Equatable {
  final String id;
  final String medicineId;
  final String? brand;
  final String? dosage;
  final String? form;
  final String? barcode;
  final String? sku;
  final int? defaultPriceXaf;
  final bool isActive;

  const MedicineVariant({
    required this.id,
    required this.medicineId,
    this.brand,
    this.dosage,
    this.form,
    this.barcode,
    this.sku,
    this.defaultPriceXaf,
    this.isActive = true,
  });

  String get label {
    final parts = <String>[
      if (brand != null && brand!.isNotEmpty) brand!,
      if (dosage != null && dosage!.isNotEmpty) dosage!,
      if (form != null && form!.isNotEmpty) form!,
    ];
    return parts.isEmpty ? id : parts.join(' · ');
  }

  factory MedicineVariant.fromJson(Map<String, dynamic> json) {
    return MedicineVariant(
      id: json['id']?.toString() ?? '',
      medicineId: json['medicine_id']?.toString() ?? '',
      brand: json['brand'] as String?,
      dosage: json['dosage'] as String?,
      form: json['form'] as String?,
      barcode: json['barcode'] as String?,
      sku: json['sku'] as String?,
      defaultPriceXaf: (json['default_price_xaf'] as num?)?.toInt(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'medicine_id': medicineId,
        'brand': brand,
        'dosage': dosage,
        'form': form,
        'barcode': barcode,
        'sku': sku,
        'default_price_xaf': defaultPriceXaf,
        'is_active': isActive,
      };

  @override
  List<Object?> get props => [id, medicineId, brand, dosage, form];
}
