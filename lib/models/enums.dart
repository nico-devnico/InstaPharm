enum StockStatus { available, lowStock, outOfStock, unknown }

extension StockStatusX on StockStatus {
  String get displayName {
    switch (this) {
      case StockStatus.available:
        return 'Disponible';
      case StockStatus.lowStock:
        return 'Stock faible';
      case StockStatus.outOfStock:
        return 'Rupture';
      case StockStatus.unknown:
        return 'Disponibilité inconnue';
    }
  }

  /// Code API / DB (jamais AVAILABLE si unknown).
  String get apiValue {
    switch (this) {
      case StockStatus.available:
        return 'AVAILABLE';
      case StockStatus.lowStock:
        return 'LOW_STOCK';
      case StockStatus.outOfStock:
        return 'OUT_OF_STOCK';
      case StockStatus.unknown:
        return 'UNKNOWN';
    }
  }

  String get dbValue {
    switch (this) {
      case StockStatus.available:
        return 'available';
      case StockStatus.lowStock:
        return 'low_stock';
      case StockStatus.outOfStock:
        return 'out_of_stock';
      case StockStatus.unknown:
        return 'unknown';
    }
  }

  /// UNKNOWN n'est jamais considéré comme commandable.
  bool get isOrderable =>
      this == StockStatus.available || this == StockStatus.lowStock;
}

/// Provenance de la donnée de stock — extensible sans refonte du modèle.
enum StockSource { manual, api, importCsv, posIntegration }

extension StockSourceX on StockSource {
  String get dbValue {
    switch (this) {
      case StockSource.manual:
        return 'MANUAL';
      case StockSource.api:
        return 'API';
      case StockSource.importCsv:
        return 'IMPORT_CSV';
      case StockSource.posIntegration:
        return 'POS_INTEGRATION';
    }
  }

  String get displayName {
    switch (this) {
      case StockSource.manual:
        return 'Saisie manuelle';
      case StockSource.api:
        return 'API pharmacie';
      case StockSource.importCsv:
        return 'Import CSV';
      case StockSource.posIntegration:
        return 'Caisse / POS';
    }
  }

  static StockSource fromString(String? value) {
    switch ((value ?? 'MANUAL').toUpperCase()) {
      case 'API':
        return StockSource.api;
      case 'IMPORT_CSV':
        return StockSource.importCsv;
      case 'POS_INTEGRATION':
        return StockSource.posIntegration;
      default:
        return StockSource.manual;
    }
  }
}

enum PharmacyStatus { open, closed, onDuty, unknown }

extension PharmacyStatusX on PharmacyStatus {
  String get displayName {
    switch (this) {
      case PharmacyStatus.open:
        return 'Ouverte';
      case PharmacyStatus.closed:
        return 'Fermée';
      case PharmacyStatus.onDuty:
        return 'Pharmacie de garde';
      case PharmacyStatus.unknown:
        return 'Horaires inconnus';
    }
  }
}

enum TravelMode { driving, walking, cycling, moto }

extension TravelModeX on TravelMode {
  String get displayName {
    switch (this) {
      case TravelMode.driving:
        return 'Voiture';
      case TravelMode.walking:
        return 'Marche';
      case TravelMode.cycling:
        return 'Vélo';
      case TravelMode.moto:
        return 'Moto-taxi';
    }
  }

  String get icon {
    switch (this) {
      case TravelMode.driving:
        return '🚗';
      case TravelMode.walking:
        return '🚶';
      case TravelMode.cycling:
        return '🚲';
      case TravelMode.moto:
        return '🛵';
    }
  }
}

enum FulfillmentType { pickup, delivery }

extension FulfillmentTypeX on FulfillmentType {
  String get displayName {
    switch (this) {
      case FulfillmentType.pickup:
        return 'Retrait en pharmacie';
      case FulfillmentType.delivery:
        return 'Livraison à domicile';
    }
  }
}

enum PaymentMethod { cash, mtnMomo, orangeMoney }

extension PaymentMethodX on PaymentMethod {
  String get displayName {
    switch (this) {
      case PaymentMethod.cash:
        return 'Espèces à la livraison';
      case PaymentMethod.mtnMomo:
        return 'MTN Mobile Money';
      case PaymentMethod.orangeMoney:
        return 'Orange Money';
    }
  }

  String get shortName {
    switch (this) {
      case PaymentMethod.cash:
        return 'Espèces';
      case PaymentMethod.mtnMomo:
        return 'MTN MoMo';
      case PaymentMethod.orangeMoney:
        return 'Orange Money';
    }
  }
}

enum OrderStatus {
  pending,
  confirmed,
  preparing,
  outForDelivery,
  readyForPickup,
  delivered,
  cancelled,
}

extension OrderStatusX on OrderStatus {
  String get displayName {
    switch (this) {
      case OrderStatus.pending:
        return 'En attente';
      case OrderStatus.confirmed:
        return 'Confirmée';
      case OrderStatus.preparing:
        return 'En préparation';
      case OrderStatus.outForDelivery:
        return 'En cours de livraison';
      case OrderStatus.readyForPickup:
        return 'Prête au retrait';
      case OrderStatus.delivered:
        return 'Livrée';
      case OrderStatus.cancelled:
        return 'Annulée';
    }
  }

  bool get isActive =>
      this != OrderStatus.delivered && this != OrderStatus.cancelled;
}
