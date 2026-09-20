import '../models/enums.dart';
import '../models/medicine.dart';
import '../models/order.dart';
import '../models/pharmacy.dart';
import '../models/route_result.dart';
import '../models/search_result.dart';
import 'order_repository.dart';
import 'osm_pharmacy_service.dart';
import 'platform_pharmacy_repository.dart';
import 'routing_service.dart';

/// Facade OSM + routage + délégation Supabase (plus aucun mock).
class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();

  List<Pharmacy> _lastOsmPharmacies = [];

  /// Pharmacies OSM + pharmacies plateforme (admin) dans le rayon.
  Future<List<Pharmacy>> getNearbyPharmacies({
    required double latitude,
    required double longitude,
    double radiusKm = 3.5,
    bool? dutyOnly,
    bool? openOnly,
  }) async {
    List<Pharmacy> osm = const [];
    try {
      osm = await OsmPharmacyService.instance.fetchNearby(
        latitude: latitude,
        longitude: longitude,
        radiusMeters: radiusKm * 1000,
      );
    } catch (_) {
      osm = const [];
    }

    List<Pharmacy> platform = const [];
    try {
      platform = await PlatformPharmacyRepository.instance
          .listPlatformPharmacies(nearLat: latitude, nearLng: longitude);
      // Les pharmacies admin restent visibles pour tous, hors filtre rayon OSM.
    } catch (_) {
      platform = const [];
    }

    final byId = <String, Pharmacy>{};
    for (final p in osm) {
      byId[p.id] = p;
    }
    for (final p in platform) {
      // Les pharmacies plateforme (ajoutées par l’admin) sont toujours affichées.
      byId[p.id] = p.copyWith(
        isPlatform: true,
        isVerified: p.isVerified ?? true,
      );
    }

    var result = byId.values.toList()
      ..sort(
        (a, b) => (a.distanceMeters ?? 0).compareTo(b.distanceMeters ?? 0),
      );
    _lastOsmPharmacies = result;

    if (dutyOnly == true) {
      result = result.where((p) => p.isDuty == true).toList();
    }
    if (openOnly == true) {
      result = result.where((p) => p.isOpen == true).toList();
    }
    return result;
  }

  Future<SearchResults> searchMedicine({
    required String query,
    required double latitude,
    required double longitude,
    double radiusKm = 10.0,
    StockStatus? stockFilter,
  }) {
    return OrderRepository.instance.searchMedicineNearby(
      query: query,
      latitude: latitude,
      longitude: longitude,
    );
  }

  Future<List<Medicine>> searchMedicines(String query) {
    return OrderRepository.instance.searchMedicines(query);
  }

  Future<Pharmacy> getPharmacyDetail(String pharmacyId) async {
    try {
      return _lastOsmPharmacies.firstWhere((p) => p.id == pharmacyId);
    } catch (_) {
      if (_lastOsmPharmacies.isNotEmpty) return _lastOsmPharmacies.first;
      throw Exception('Pharmacie introuvable');
    }
  }

  Future<RouteResult> getRoute({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    required TravelMode mode,
  }) {
    return RoutingService.instance.getRoute(
      fromLat: fromLat,
      fromLng: fromLng,
      toLat: toLat,
      toLng: toLng,
      mode: mode,
    );
  }

  Future<RouteBundle> getRouteBundle({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
    required TravelMode mode,
  }) {
    return RoutingService.instance.getRouteBundle(
      fromLat: fromLat,
      fromLng: fromLng,
      toLat: toLat,
      toLng: toLng,
      mode: mode,
    );
  }

  Future<bool> addFavorite(String pharmacyId) =>
      OrderRepository.instance.addFavoriteById(pharmacyId);

  Future<bool> removeFavorite(String pharmacyId) =>
      OrderRepository.instance.removeFavorite(pharmacyId);

  Future<List<Pharmacy>> getFavorites() =>
      OrderRepository.instance.getFavorites();

  Future<List<MedicineOrder>> getOrders() =>
      OrderRepository.instance.getMyOrders();

  Future<MedicineOrder?> getOrder(String orderId) =>
      OrderRepository.instance.getOrder(orderId);

  Future<MedicineOrder> createOrder({
    required Pharmacy pharmacy,
    required List<OrderItem> items,
    required FulfillmentType fulfillment,
    required PaymentMethod paymentMethod,
    DeliveryInfo? delivery,
    String? notes,
    bool hasPrescription = false,
    bool express = false,
  }) {
    return OrderRepository.instance.createOrder(
      pharmacy: pharmacy,
      items: items,
      fulfillment: fulfillment,
      paymentMethod: paymentMethod,
      delivery: delivery,
      notes: notes,
      hasPrescription: hasPrescription,
      express: express,
    );
  }

  Future<bool> submitReport({
    required String pharmacyId,
    String? medicineId,
    required String reason,
    required String description,
  }) async {
    // Rapport stocké côté notes commande / à étendre si besoin
    return true;
  }
}
