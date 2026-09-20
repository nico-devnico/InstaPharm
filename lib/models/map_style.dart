/// Styles de fond et calques de détails pour la carte.
enum MapBaseStyle {
  /// Plan standard (OpenStreetMap)
  streets,
  /// Imagerie satellite
  satellite,
}

extension MapBaseStyleX on MapBaseStyle {
  String get label {
    switch (this) {
      case MapBaseStyle.streets:
        return 'Par défaut';
      case MapBaseStyle.satellite:
        return 'Satellite';
    }
  }

  String get urlTemplate {
    switch (this) {
      case MapBaseStyle.streets:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapBaseStyle.satellite:
        // Esri World Imagery (tuiles libres pour affichage carte)
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'World_Imagery/MapServer/tile/{z}/{y}/{x}';
    }
  }

  int get maxNativeZoom {
    switch (this) {
      case MapBaseStyle.streets:
        return 19;
      case MapBaseStyle.satellite:
        return 18;
    }
  }
}

/// Options de détails superposés (type Google Maps).
class MapDetailOptions {
  /// Coloration trafic / bouchons sur l’itinéraire
  final bool traffic;
  /// Calque transport en commun
  final bool transit;
  /// Accès Street View (ouvre la vue immersive)
  final bool streetView;

  const MapDetailOptions({
    // Trafic OFF par défaut : beaucoup de polylines colorées figent la carte
    this.traffic = false,
    this.transit = false,
    this.streetView = false,
  });

  MapDetailOptions copyWith({
    bool? traffic,
    bool? transit,
    bool? streetView,
  }) {
    return MapDetailOptions(
      traffic: traffic ?? this.traffic,
      transit: transit ?? this.transit,
      streetView: streetView ?? this.streetView,
    );
  }

  /// Tuiles transport en commun (ÖPNV / Memomaps).
  static const transitTileUrl =
      'https://tile.memomaps.de/tilegen/{z}/{x}/{y}.png';
}
