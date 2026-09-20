import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/coordinates.dart';
import '../models/enums.dart';
import '../models/inventory.dart';
import '../models/medicine.dart';
import '../models/pharmacy.dart';
import '../models/search_result.dart';
import 'location_service.dart';
import 'routing_service.dart';
import 'supabase_service.dart';

/// Pharmacies enregistrées par l’administrateur + leurs inventaires.
/// Cœur métier : recherche médicament → interrogation de toutes les bases stock.
class PlatformPharmacyRepository {
  PlatformPharmacyRepository._();
  static final PlatformPharmacyRepository instance =
      PlatformPharmacyRepository._();

  SupabaseClient get _db => SupabaseService.client;

  /// Toutes les pharmacies partenaires actives sur la plateforme.
  Future<List<Pharmacy>> listPlatformPharmacies({
    double? nearLat,
    double? nearLng,
  }) async {
    final rows = await _db
        .from('pharmacies')
        .select()
        .eq('is_platform', true)
        .eq('is_active', true)
        .order('name');

    final list = <Pharmacy>[];
    for (final e in rows as List) {
      final raw = Map<String, dynamic>.from(e as Map);
      final st = raw['platform_status']?.toString();
      if (st == 'SUSPENDED' || st == 'REJECTED') continue;
      list.add(_pharmacyFromRow(raw));
    }

    if (nearLat != null && nearLng != null) {
      return list
          .map((p) {
            if (p.coordinates == null) return p;
            final d = LocationService.distanceBetween(
              nearLat,
              nearLng,
              p.coordinates!.latitude,
              p.coordinates!.longitude,
            );
            return p.copyWith(
              distanceMeters: d,
              travelTimeSeconds:
                  RoutingService.estimateUrbanTravelSeconds(d),
            );
          })
          .toList()
        ..sort(
          (a, b) =>
              (a.distanceMeters ?? 1e9).compareTo(b.distanceMeters ?? 1e9),
        );
    }
    return list;
  }

  /// Enregistrement d’une pharmacie par l’administrateur.
  Future<Pharmacy> registerPharmacy({
    required String name,
    String? address,
    String? city,
    double? latitude,
    double? longitude,
    String? phone,
    String? email,
    bool isDuty = false,
    bool isOpen = true,
    List<String> services = const ['Livraison'],
    String? ownerUserId,
  }) async {
    final user = _db.auth.currentUser;
    final id =
        'plat-${DateTime.now().millisecondsSinceEpoch}-${name.hashCode.abs()}';
    final row = {
      'id': id,
      'name': name.trim(),
      'address': address?.trim(),
      'city': city?.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'phone': phone?.trim(),
      'email': email?.trim(),
      'is_duty': isDuty,
      'is_open': isOpen,
      'is_verified': true,
      'is_platform': true,
      'services': services,
      'owner_user_id': ownerUserId,
      'registered_by': user?.id,
    };
    await _db.from('pharmacies').upsert(row);
    return _pharmacyFromRow(row);
  }

  Future<void> updatePharmacy(Pharmacy p) async {
    await _db.from('pharmacies').update({
      'name': p.name,
      'address': p.address,
      'city': p.city,
      'latitude': p.coordinates?.latitude,
      'longitude': p.coordinates?.longitude,
      'phone': p.phone,
      'email': p.email,
      'is_duty': p.isDuty ?? false,
      'is_open': p.isOpen ?? true,
      'is_verified': true,
      'is_platform': true,
      'services': p.services ?? ['Livraison'],
    }).eq('id', p.id);
  }

  Future<void> deletePharmacy(String pharmacyId) async {
    await _db.from('pharmacies').delete().eq('id', pharmacyId).eq(
          'is_platform',
          true,
        );
  }

  /// Pharmacie liée au pharmacien connecté (owner_user_id).
  Future<Pharmacy?> getMyPharmacy() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _db
        .from('pharmacies')
        .select()
        .eq('is_platform', true)
        .eq('owner_user_id', uid)
        .maybeSingle();
    if (row == null) return null;
    return _pharmacyFromRow(Map<String, dynamic>.from(row));
  }

  Future<void> assignOwner({
    required String pharmacyId,
    required String ownerUserId,
  }) async {
    await _db.from('pharmacies').update({
      'owner_user_id': ownerUserId,
    }).eq('id', pharmacyId);
  }

  Future<List<Medicine>> listMedicines({String? query}) async {
    if (query == null || query.trim().isEmpty) {
      final rows = await _db.from('medicines').select().order('name').limit(80);
      return (rows as List)
          .map((e) => Medicine.fromJson(_medMap(e as Map)))
          .toList();
    }
    final q = query.trim();
    final rows = await _db
        .from('medicines')
        .select()
        .or('name.ilike.%$q%,brand.ilike.%$q%,category.ilike.%$q%')
        .limit(40);
    return (rows as List)
        .map((e) => Medicine.fromJson(_medMap(e as Map)))
        .toList();
  }

  Future<Medicine> addMedicine({
    required String name,
    String? brand,
    String? dosage,
    String? form,
    String? category,
    int priceXaf = 0,
    bool requiresPrescription = false,
  }) async {
    final row = await _db.from('medicines').insert({
      'name': name.trim(),
      'brand': brand?.trim(),
      'dosage': dosage?.trim(),
      'form': form?.trim(),
      'category': category?.trim(),
      'price_xaf': priceXaf,
      'requires_prescription': requiresPrescription,
    }).select().single();
    return Medicine.fromJson(_medMap(row));
  }

  Future<List<InventoryLine>> getPharmacyInventory(String pharmacyId) async {
    List rows;
    try {
      rows = await _db
          .from('inventory')
          .select('*, medicines(*), medicine_variants(*)')
          .eq('pharmacy_id', pharmacyId)
          .order('updated_at', ascending: false) as List;
    } catch (_) {
      rows = await _db
          .from('inventory')
          .select('*, medicines(*)')
          .eq('pharmacy_id', pharmacyId)
          .order('updated_at', ascending: false) as List;
    }
    return rows.map((raw) {
      final e = Map<String, dynamic>.from(raw as Map);
      final med = e['medicines'] as Map?;
      final inv = Inventory.fromJson({
        ...e,
        'medicines': med,
      });
      return InventoryLine(
        inventory: inv,
        medicine: med != null
            ? Medicine.fromJson(_medMap(med))
            : Medicine(
                id: e['medicine_id']?.toString() ?? '',
                name: 'Médicament',
              ),
      );
    }).toList();
  }

  Future<void> upsertInventory({
    required String pharmacyId,
    required String medicineId,
    required StockStatus status,
    int? quantity,
    int? unitPriceXaf,
    StockSource stockSource = StockSource.manual,
    int? lowStockThreshold,
    String? medicineVariantId,
  }) async {
    // UNKNOWN ne doit jamais être dérivé en AVAILABLE côté client
    final effectiveStatus = status;
    final variantId = medicineVariantId ?? medicineId;
    await _db.from('inventory').upsert({
      'pharmacy_id': pharmacyId,
      'medicine_id': medicineId,
      'medicine_variant_id': variantId,
      'status': effectiveStatus.dbValue,
      'quantity': quantity,
      'unit_price_xaf': unitPriceXaf,
      'stock_source': stockSource.dbValue,
      if (lowStockThreshold != null) 'low_stock_threshold': lowStockThreshold,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'pharmacy_id,medicine_id');
  }

  /// Mise à jour rapide quantité seule (dérive le statut sauf si UNKNOWN).
  Future<void> quickUpdateQuantity({
    required String pharmacyId,
    required String medicineId,
    required int quantity,
    StockStatus? currentStatus,
    String? medicineVariantId,
  }) async {
    StockStatus next;
    if (currentStatus == StockStatus.unknown) {
      next = StockStatus.unknown;
    } else if (quantity <= 0) {
      next = StockStatus.outOfStock;
    } else if (quantity <= 5) {
      next = StockStatus.lowStock;
    } else {
      next = StockStatus.available;
    }
    await upsertInventory(
      pharmacyId: pharmacyId,
      medicineId: medicineId,
      medicineVariantId: medicineVariantId,
      status: next,
      quantity: quantity,
    );
  }

  /// Ajoute un médicament au catalogue + ligne de stock pharmacie.
  Future<InventoryLine> addMedicineToPharmacyStock({
    required String pharmacyId,
    required String name,
    String? brand,
    String? dosage,
    String? form,
    String? category,
    int priceXaf = 0,
    int quantity = 0,
    StockStatus status = StockStatus.available,
    bool requiresPrescription = false,
  }) async {
    final medicine = await addMedicine(
      name: name,
      brand: brand,
      dosage: dosage,
      form: form,
      category: category,
      priceXaf: priceXaf,
      requiresPrescription: requiresPrescription,
    );

    // Créer / lier la variante (id = medicine.id en migration 1:1)
    try {
      await _db.from('medicine_variants').upsert({
        'id': medicine.id,
        'medicine_id': medicine.id,
        'brand': brand,
        'dosage': dosage,
        'form': form,
        'default_price_xaf': priceXaf,
      });
    } catch (_) {
      // Table absente tant que stock_system.sql n'est pas appliqué
    }

    final effective = status == StockStatus.unknown
        ? StockStatus.unknown
        : (quantity <= 0
            ? StockStatus.outOfStock
            : (quantity <= 5 ? StockStatus.lowStock : status));

    await upsertInventory(
      pharmacyId: pharmacyId,
      medicineId: medicine.id,
      medicineVariantId: medicine.id,
      status: effective,
      quantity: quantity,
      unitPriceXaf: priceXaf,
    );

    return InventoryLine(
      inventory: Inventory(
        pharmacyId: pharmacyId,
        medicineId: medicine.id,
        medicineVariantId: medicine.id,
        status: effective,
        quantity: quantity,
        unitPriceXaf: priceXaf,
        lastUpdatedAt: DateTime.now(),
      ),
      medicine: medicine,
    );
  }

  /// Remplit le stock d’une pharmacie avec tout le catalogue (admin).
  Future<int> seedCatalogInventory(String pharmacyId) async {
    final meds = await listMedicines();
    var n = 0;
    for (final m in meds) {
      await upsertInventory(
        pharmacyId: pharmacyId,
        medicineId: m.id,
        medicineVariantId: m.id,
        status: StockStatus.available,
        quantity: 20,
        unitPriceXaf: m.priceXaf ?? 1000,
        stockSource: StockSource.manual,
      );
      n++;
    }
    return n;
  }

  /// Recherche principale : médicament → toutes les bases inventaire plateforme.
  Future<SearchResults> searchMedicineAcrossPharmacies({
    required String query,
    required double latitude,
    required double longitude,
  }) async {
    final meds = await listMedicines(query: query);
    if (meds.isEmpty) {
      return SearchResults(
        results: const [],
        searchedMedicine: null,
        totalCount: 0,
        availableCount: 0,
        searchLatitude: latitude,
        searchLongitude: longitude,
      );
    }

    // Médicament le plus pertinent (correspondance nom exacte prioritaire)
    final q = query.trim().toLowerCase();
    meds.sort((a, b) {
      final ae = a.name.toLowerCase() == q ? 0 : 1;
      final be = b.name.toLowerCase() == q ? 0 : 1;
      if (ae != be) return ae.compareTo(be);
      final as_ = a.name.toLowerCase().startsWith(q) ? 0 : 1;
      final bs = b.name.toLowerCase().startsWith(q) ? 0 : 1;
      return as_.compareTo(bs);
    });
    final medicine = meds.first;
    final medicineIds = meds.take(8).map((m) => m.id).toList();

    // Interroge l’inventaire de TOUTES les pharmacies enregistrées
    final rows = await _db
        .from('inventory')
        .select('*, pharmacies!inner(*)')
        .inFilter('medicine_id', medicineIds)
        .eq('pharmacies.is_platform', true);

    final results = <PharmacySearchResult>[];
    final seenPharmacy = <String>{};

    for (final raw in (rows as List)) {
      final e = Map<String, dynamic>.from(raw as Map);
      final phMap = e['pharmacies'];
      if (phMap is! Map) continue;
      final pharmacyId = e['pharmacy_id']?.toString() ?? '';
      final medId = e['medicine_id']?.toString() ?? '';
      // Une ligne par pharmacie : garder le stock du médicament principal si possible
      if (seenPharmacy.contains(pharmacyId) && medId != medicine.id) {
        continue;
      }
      if (seenPharmacy.contains(pharmacyId) && medId == medicine.id) {
        // remplacera plus bas si déjà une autre ligne
      }

      final pharmacy = _pharmacyFromRow(Map<String, dynamic>.from(phMap));
      double? distance;
      int? travel;
      if (pharmacy.coordinates != null) {
        distance = LocationService.distanceBetween(
          latitude,
          longitude,
          pharmacy.coordinates!.latitude,
          pharmacy.coordinates!.longitude,
        );
        travel = RoutingService.estimateUrbanTravelSeconds(distance);
      }

      final status = _stockFromString(e['status']?.toString());
      final qty = e['quantity'] as int?;
      final reserved = (e['reserved_quantity'] as num?)?.toInt() ?? 0;
      final price =
          (e['unit_price_xaf'] as num?)?.toInt() ?? medicine.priceXaf;

      // UNKNOWN : score minimal, jamais traité comme disponible
      final stockScore = status == StockStatus.unknown
          ? 0.0
          : status == StockStatus.available
              ? 1.0
              : status == StockStatus.lowStock
                  ? 0.55
                  : 0.05;
      final distanceScore =
          1.0 - ((distance ?? 8000) / 15000).clamp(0.0, 1.0);
      final openBonus = pharmacy.isOpen == true || pharmacy.isDuty == true
          ? 0.12
          : 0.0;
      final relevance = stockScore * 0.5 + distanceScore * 0.38 + openBonus;

      final lineMedicine = medId == medicine.id
          ? medicine
          : (meds.where((m) => m.id == medId).isEmpty
              ? medicine
              : meds.firstWhere((m) => m.id == medId));

      DateTime? updatedAt;
      final rawUpdated = e['updated_at']?.toString();
      if (rawUpdated != null) updatedAt = DateTime.tryParse(rawUpdated);

      final result = PharmacySearchResult(
        pharmacy: pharmacy.copyWith(
          distanceMeters: distance,
          travelTimeSeconds: travel,
          isVerified: true,
        ),
        medicine: lineMedicine,
        inventory: Inventory(
          pharmacyId: pharmacyId,
          medicineId: medId,
          medicineVariantId: e['medicine_variant_id']?.toString() ?? medId,
          status: status,
          quantity: qty,
          reservedQuantity: reserved,
          unitPriceXaf: price,
          stockSource:
              StockSourceX.fromString(e['stock_source']?.toString()),
          lastUpdatedAt: updatedAt,
          lastUpdatedSeconds: updatedAt != null
              ? updatedAt.millisecondsSinceEpoch ~/ 1000
              : DateTime.now().millisecondsSinceEpoch ~/ 1000,
        ),
        relevanceScore: relevance,
        isBestMatch: false,
      );

      if (seenPharmacy.contains(pharmacyId)) {
        final idx = results.indexWhere((r) => r.pharmacy.id == pharmacyId);
        if (idx >= 0 && medId == medicine.id) {
          results[idx] = result;
        }
      } else {
        seenPharmacy.add(pharmacyId);
        results.add(result);
      }
    }

    results.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));
    if (results.isNotEmpty) {
      final best = results.first;
      results[0] = PharmacySearchResult(
        pharmacy: best.pharmacy,
        medicine: best.medicine,
        inventory: best.inventory,
        relevanceScore: best.relevanceScore,
        isBestMatch: true,
      );
    }

    return SearchResults(
      results: results,
      searchedMedicine: medicine,
      totalCount: results.length,
      availableCount: results
          .where((r) => r.stockStatus.isOrderable)
          .length,
      searchLatitude: latitude,
      searchLongitude: longitude,
    );
  }

  Pharmacy _pharmacyFromRow(Map<String, dynamic> e) {
    return Pharmacy(
      id: e['id']?.toString() ?? '',
      name: e['name']?.toString() ?? '',
      address: e['address']?.toString(),
      city: e['city']?.toString(),
      postalCode: e['postal_code']?.toString(),
      coordinates: (e['latitude'] != null && e['longitude'] != null)
          ? Coordinates(
              latitude: (e['latitude'] as num).toDouble(),
              longitude: (e['longitude'] as num).toDouble(),
            )
          : null,
      phone: e['phone']?.toString(),
      email: e['email']?.toString(),
      website: e['website']?.toString(),
      rating: (e['rating'] as num?)?.toDouble(),
      reviewCount: e['review_count'] as int?,
      isDuty: e['is_duty'] as bool? ?? false,
      isOpen: e['is_open'] as bool? ?? true,
      services: (e['services'] as List?)?.map((s) => s.toString()).toList(),
      isVerified: e['is_verified'] as bool? ?? e['is_platform'] as bool? ?? true,
      isPlatform: e['is_platform'] as bool? ?? true,
      ownerUserId: e['owner_user_id']?.toString(),
    );
  }

  Map<String, dynamic> _medMap(Map e) => {
        'id': e['id']?.toString() ?? '',
        'name': e['name'],
        'brand': e['brand'],
        'dosage': e['dosage'],
        'form': e['form'],
        'category': e['category'],
        'description': e['description'],
        'requires_prescription': e['requires_prescription'],
        'price_xaf': e['price_xaf'],
      };

  StockStatus _stockFromString(String? s) {
    switch (s) {
      case 'available':
        return StockStatus.available;
      case 'low_stock':
        return StockStatus.lowStock;
      case 'out_of_stock':
        return StockStatus.outOfStock;
      default:
        return StockStatus.unknown;
    }
  }
}

class InventoryLine {
  final Inventory inventory;
  final Medicine medicine;

  const InventoryLine({required this.inventory, required this.medicine});
}
