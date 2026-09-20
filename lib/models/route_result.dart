import 'package:equatable/equatable.dart';
import 'coordinates.dart';
import 'enums.dart';

/// Niveau de fluidité d’un segment routier (dérivé OSRM annotations + MLD).
enum CongestionLevel {
  /// Circulation fluide
  free,
  /// Ralentissement
  slow,
  /// Embouteillage
  congested,
  /// Quasi à l’arrêt
  jammed,
}

extension CongestionLevelX on CongestionLevel {
  String get displayName {
    switch (this) {
      case CongestionLevel.free:
        return 'Fluide';
      case CongestionLevel.slow:
        return 'Ralentissement';
      case CongestionLevel.congested:
        return 'Bouchon';
      case CongestionLevel.jammed:
        return 'Embouteillage fort';
    }
  }

  String get shortLabel {
    switch (this) {
      case CongestionLevel.free:
        return 'OK';
      case CongestionLevel.slow:
        return 'Lent';
      case CongestionLevel.congested:
        return 'Bouchon';
      case CongestionLevel.jammed:
        return 'Bloqué';
    }
  }

  bool get isAlert =>
      this == CongestionLevel.congested || this == CongestionLevel.jammed;
}

/// Segment d’itinéraire coloré selon le trafic (annotations OSRM).
class TrafficSegment extends Equatable {
  final List<Coordinates> points;
  final CongestionLevel level;
  final double distanceMeters;
  final int durationSeconds;
  final double? speedKmh;

  const TrafficSegment({
    required this.points,
    required this.level,
    required this.distanceMeters,
    required this.durationSeconds,
    this.speedKmh,
  });

  @override
  List<Object?> get props => [level, distanceMeters, durationSeconds, speedKmh];
}

class RouteResult extends Equatable {
  final double distanceMeters;
  final int durationSeconds;
  final List<Coordinates> geometry;
  final TravelMode travelMode;
  final List<RouteStep>? steps;

  /// Segments colorés trafic (MLD + annotations). Vide si indisponible.
  final List<TrafficSegment> trafficSegments;

  /// Durée « libre » estimée (sans bouchon), si calculable.
  final int? freeFlowDurationSeconds;

  /// true si le moteur OSRM MLD personnalisé (customize) a été utilisé.
  final bool fromTrafficEngine;

  /// Libellé UI (Itinéraire principal, Raccourci, Alternative…).
  final String? label;

  /// true si c’est un raccourci / itinéraire alternatif navigable.
  final bool isShortcut;

  const RouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.geometry,
    required this.travelMode,
    this.steps,
    this.trafficSegments = const [],
    this.freeFlowDurationSeconds,
    this.fromTrafficEngine = false,
    this.label,
    this.isShortcut = false,
  });

  RouteResult copyWith({
    double? distanceMeters,
    int? durationSeconds,
    List<Coordinates>? geometry,
    TravelMode? travelMode,
    List<RouteStep>? steps,
    List<TrafficSegment>? trafficSegments,
    int? freeFlowDurationSeconds,
    bool? fromTrafficEngine,
    String? label,
    bool? isShortcut,
  }) {
    return RouteResult(
      distanceMeters: distanceMeters ?? this.distanceMeters,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      geometry: geometry ?? this.geometry,
      travelMode: travelMode ?? this.travelMode,
      steps: steps ?? this.steps,
      trafficSegments: trafficSegments ?? this.trafficSegments,
      freeFlowDurationSeconds:
          freeFlowDurationSeconds ?? this.freeFlowDurationSeconds,
      fromTrafficEngine: fromTrafficEngine ?? this.fromTrafficEngine,
      label: label ?? this.label,
      isShortcut: isShortcut ?? this.isShortcut,
    );
  }

  bool get hasCongestion =>
      trafficSegments.any((s) => s.level.isAlert) ||
      (freeFlowDurationSeconds != null &&
          durationSeconds > freeFlowDurationSeconds! * 1.35);

  /// Minutes de retard estimées vs circulation fluide.
  int get delayMinutes {
    if (freeFlowDurationSeconds == null) {
      final congestedMeters = trafficSegments
          .where((s) => s.level.isAlert)
          .fold<double>(0, (a, s) => a + s.distanceMeters);
      if (congestedMeters <= 0) return 0;
      return (congestedMeters / 1000 / 10 * 60).round().clamp(1, 90);
    }
    final delay = durationSeconds - freeFlowDurationSeconds!;
    if (delay <= 30) return 0;
    return (delay / 60).round().clamp(1, 120);
  }

  CongestionLevel get worstCongestion {
    var worst = CongestionLevel.free;
    for (final s in trafficSegments) {
      if (s.level.index > worst.index) worst = s.level;
    }
    if (hasCongestion && worst == CongestionLevel.free) {
      return CongestionLevel.congested;
    }
    return worst;
  }

  String get congestionSummary {
    if (!hasCongestion) return 'Circulation fluide';
    final delay = delayMinutes;
    final label = worstCongestion.displayName;
    if (delay > 0) return '$label · +$delay min';
    return label;
  }

  String get durationFormatted {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '${hours}h ${mins}min' : '${hours}h';
  }

  String get distanceFormatted {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  factory RouteResult.fromJson(Map<String, dynamic> json, TravelMode mode) {
    final coords = (json['geometry'] as List<dynamic>?) ??
        (json['route'] as List<dynamic>?);
    final geometry = <Coordinates>[];
    if (coords != null) {
      for (final c in coords) {
        if (c is List && c.length >= 2) {
          geometry.add(Coordinates(
            latitude: (c[1] as num).toDouble(),
            longitude: (c[0] as num).toDouble(),
          ));
        } else if (c is Map) {
          geometry.add(Coordinates.fromJson(c as Map<String, dynamic>));
        }
      }
    }
    return RouteResult(
      distanceMeters: (json['distance_meters'] as num?)?.toDouble() ??
          (json['distance'] as num?)?.toDouble() ??
          0,
      durationSeconds: (json['duration_seconds'] as int?) ??
          (json['duration'] as int?) ??
          0,
      geometry: geometry,
      travelMode: mode,
    );
  }

  @override
  List<Object?> get props => [
        distanceMeters,
        durationSeconds,
        travelMode,
        hasCongestion,
        isShortcut,
        label,
      ];
}

/// Itinéraire principal + raccourcis navigables (alternatives OSRM).
class RouteBundle extends Equatable {
  final RouteResult primary;
  final List<RouteResult> shortcuts;

  const RouteBundle({
    required this.primary,
    this.shortcuts = const [],
  });

  List<RouteResult> get all => [primary, ...shortcuts];

  @override
  List<Object?> get props => [primary, shortcuts];
}

class RouteStep extends Equatable {
  final String instruction;
  final double distanceMeters;
  final int durationSeconds;
  final CongestionLevel? congestion;

  const RouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
    this.congestion,
  });

  @override
  List<Object?> get props => [
        instruction,
        distanceMeters,
        durationSeconds,
        congestion,
      ];
}
