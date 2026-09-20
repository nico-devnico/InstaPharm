import 'package:equatable/equatable.dart';
import 'pharmacy.dart';
import 'inventory.dart';
import 'medicine.dart';
import 'enums.dart';

class PharmacySearchResult extends Equatable {
  final Pharmacy pharmacy;
  final Medicine? medicine;
  final Inventory? inventory;
  final double relevanceScore;
  final bool isBestMatch;

  const PharmacySearchResult({
    required this.pharmacy,
    this.medicine,
    this.inventory,
    this.relevanceScore = 0.0,
    this.isBestMatch = false,
  });

  StockStatus get stockStatus => inventory?.status ?? StockStatus.unknown;

  factory PharmacySearchResult.fromJson(Map<String, dynamic> json) {
    return PharmacySearchResult(
      pharmacy: Pharmacy.fromJson(json['pharmacy'] as Map<String, dynamic>? ?? {}),
      medicine: json['medicine'] != null
          ? Medicine.fromJson(json['medicine'] as Map<String, dynamic>)
          : null,
      inventory: json['inventory'] != null
          ? Inventory.fromJson(json['inventory'] as Map<String, dynamic>)
          : null,
      relevanceScore: (json['relevance_score'] as num?)?.toDouble() ?? 0.0,
      isBestMatch: (json['is_best_match'] as bool?) ?? false,
    );
  }

  @override
  List<Object?> get props => [
        pharmacy,
        medicine,
        inventory,
        relevanceScore,
        isBestMatch,
      ];
}

class SearchResults extends Equatable {
  final List<PharmacySearchResult> results;
  final Medicine? searchedMedicine;
  final int totalCount;
  final int availableCount;
  final double? searchLatitude;
  final double? searchLongitude;

  const SearchResults({
    required this.results,
    this.searchedMedicine,
    required this.totalCount,
    required this.availableCount,
    this.searchLatitude,
    this.searchLongitude,
  });

  factory SearchResults.fromJson(Map<String, dynamic> json) {
    final list = (json['results'] as List<dynamic>?) ?? [];
    return SearchResults(
      results: list
          .map((e) => PharmacySearchResult.fromJson(e as Map<String, dynamic>))
          .toList(),
      searchedMedicine: json['medicine'] != null
          ? Medicine.fromJson(json['medicine'] as Map<String, dynamic>)
          : null,
      totalCount: (json['total_count'] as int?) ?? list.length,
      availableCount: (json['available_count'] as int?) ?? 0,
      searchLatitude: (json['search_latitude'] as num?)?.toDouble(),
      searchLongitude: (json['search_longitude'] as num?)?.toDouble(),
    );
  }

  @override
  List<Object?> get props => [
        results,
        searchedMedicine,
        totalCount,
        availableCount,
      ];
}
