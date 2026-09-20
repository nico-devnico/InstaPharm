import 'package:equatable/equatable.dart';

class Medicine extends Equatable {
  final String id;
  final String name;
  final String? brand;
  final String? dosage;
  final String? form;
  final String? category;
  final String? description;
  final String? imageUrl;
  final bool? requiresPrescription;
  /// Prix unitaire indicatif en FCFA (XAF).
  final int? priceXaf;

  const Medicine({
    required this.id,
    required this.name,
    this.brand,
    this.dosage,
    this.form,
    this.category,
    this.description,
    this.imageUrl,
    this.requiresPrescription,
    this.priceXaf,
  });

  String get fullName {
    final parts = <String>[name];
    if (brand != null && brand!.isNotEmpty) parts.add('($brand)');
    if (dosage != null && dosage!.isNotEmpty) parts.add(dosage!);
    return parts.join(' ');
  }

  factory Medicine.fromJson(Map<String, dynamic> json) {
    return Medicine(
      id: json['id'] as String? ?? json['uuid'] as String? ?? '',
      name: json['name'] as String? ?? '',
      brand: json['brand'] as String?,
      dosage: json['dosage'] as String?,
      form: json['form'] as String?,
      category: json['category'] as String?,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String?,
      requiresPrescription: json['requires_prescription'] as bool?,
      priceXaf: (json['price_xaf'] as num?)?.toInt() ??
          (json['price'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'brand': brand,
        'dosage': dosage,
        'form': form,
        'category': category,
        'description': description,
        'image_url': imageUrl,
        'requires_prescription': requiresPrescription,
        'price_xaf': priceXaf,
      };

  @override
  List<Object?> get props => [
        id,
        name,
        brand,
        dosage,
        form,
        category,
        priceXaf,
      ];
}
