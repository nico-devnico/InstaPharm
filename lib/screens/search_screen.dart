import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/cameroon.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/nav_utils.dart';
import '../core/utils/pharmacy_detail_nav.dart';
import '../core/utils/responsive.dart';
import '../models/medicine.dart';
import '../models/search_result.dart';
import '../models/enums.dart';
import '../providers/location_providers.dart';
import '../services/location_service.dart';
import '../services/order_repository.dart';
import '../services/user_activity_repository.dart';
import '../widgets/pharmacy_card.dart';
import '../widgets/skeleton_widgets.dart';
import '../widgets/state_widgets.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');
final searchResultsProvider = FutureProvider<SearchResults?>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty || query.length < 2) return null;
  final live = ref.watch(liveCoordinatesProvider);
  final loc = live ?? await LocationService.instance.getCurrentLocation();
  final lat = loc?.latitude ?? CameroonDefaults.defaultLocation.latitude;
  final lng = loc?.longitude ?? CameroonDefaults.defaultLocation.longitude;
  await UserActivityRepository.instance.logSearch(query);
  // Interroge les inventaires de toutes les pharmacies enregistrées (admin).
  return OrderRepository.instance.searchMedicineNearby(
    query: query,
    latitude: lat,
    longitude: lng,
  );
});

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _stockFilter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
    _controller.addListener(() {
      ref.read(searchQueryProvider.notifier).state = _controller.text;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final resultsAsync = ref.watch(searchResultsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            Expanded(
              child: query.isEmpty || query.length < 2
                  ? _buildSuggestions(context)
                  : resultsAsync.when(
                      loading: () => const SearchResultSkeletonList(),
                      error: (e, _) => ErrorState(
                        message: e.toString(),
                        onAction: () => ref.invalidate(searchResultsProvider),
                      ),
                      data: (data) {
                        if (data == null) return const SizedBox.shrink();
                        return _buildResults(data, context);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon:
                const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          Expanded(
            child: Hero(
              tag: 'search-field',
              child: Material(
                color: Colors.transparent,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    style: AppTypography.textTheme.bodyMedium,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Paracétamol, Ibuprofène...',
                      hintStyle: AppTypography.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.textTertiary),
                      prefixIcon: const Icon(Icons.search_rounded,
                          color: AppColors.textSecondary, size: 20),
                      suffixIcon: _controller.text.isNotEmpty
                          ? IconButton(
                              onPressed: () => _controller.clear(),
                              icon: const Icon(Icons.close_rounded,
                                  color: AppColors.textTertiary, size: 18),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 13),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions(BuildContext context) {
    final padH = Responsive.padH(context);
    final suggestions = [
      'Paracétamol 500 mg',
      'Coartem',
      'Amoxicilline',
      'Sels de réhydratation',
      'Artésunate',
      'Flagyl',
      'Ventoline',
      'Moustiquaire',
    ];

    return ListView(
      padding: EdgeInsets.symmetric(horizontal: padH),
      children: [
        const SizedBox(height: 8),
        Text(
          'Tapez un médicament : l’app interroge le stock de toutes '
          'les pharmacies partenaires enregistrées.',
          style: AppTypography.textTheme.bodySmall?.copyWith(
            color: AppColors.textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Recherches populaires',
          style: AppTypography.textTheme.titleMedium
              ?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: suggestions
              .map((s) => GestureDetector(
                    onTap: () => _controller.text = s,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                        boxShadow: AppColors.cardShadow,
                      ),
                      child: Text(
                        s,
                        style: AppTypography.textTheme.labelMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 28),
        Text(
          'Catégories',
          style: AppTypography.textTheme.titleMedium
              ?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        // Grille 2×4 responsive (2 items par ligne)
        _buildCategoryGrid(context, [
          (Icons.medication_liquid_rounded, 'Douleur & Fièvre'),
          (Icons.biotech_rounded, 'Antibiotiques'),
          (Icons.self_improvement_rounded, 'Vitamines'),
          (Icons.air_rounded, 'Allergie'),
          (Icons.bedtime_rounded, 'Sommeil'),
          (Icons.spa_rounded, 'Digestion'),
          (Icons.masks_rounded, 'Respiratoire'),
          (Icons.favorite_border_rounded, 'Cœur'),
        ]),
      ],
    );
  }

  Widget _buildCategoryGrid(
      BuildContext context, List<(IconData, String)> items) {
    // Grille en 2 colonnes de 4 lignes, toujours 2 items par ligne
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      final rowItems = items.sublist(i, (i + 2).clamp(0, items.length));
      rows.add(
        Row(
          children: [
            for (var j = 0; j < rowItems.length; j++) ...[
              Expanded(child: _buildCategoryItem(rowItems[j])),
              if (j < rowItems.length - 1) const SizedBox(width: 10),
            ],
            // Rembourrage si nombre impair
            if (rowItems.length < 2) const Expanded(child: SizedBox()),
          ],
        ),
      );
      if (i + 2 < items.length) rows.add(const SizedBox(height: 10));
    }
    return Column(children: rows);
  }

  Widget _buildCategoryItem((IconData, String) item) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _controller.text = item.$2,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    Icon(item.$1, color: AppColors.primaryBlue, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                item.$2,
                style: AppTypography.textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(SearchResults data, BuildContext context) {
    final med = data.searchedMedicine;
    final filtered = _applyStockFilter(data.results);

    return Column(
      children: [
        if (med != null) _buildMedicineHeader(med, data, context),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildFilter('all', 'Toutes (${data.totalCount})', null),
                const SizedBox(width: 8),
                _buildFilter(
                  'available',
                  'Disponibles (${data.availableCount})',
                  AppColors.available,
                ),
                const SizedBox(width: 8),
                _buildFilter('low', 'Stock faible', AppColors.lowStock),
                const SizedBox(width: 8),
                _buildFilter('out', 'Rupture', AppColors.outOfStock),
              ],
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: EmptyState(
                    icon: Icons.inbox_rounded,
                    title: 'Aucun stock trouvé',
                    subtitle:
                        'Aucune pharmacie partenaire ne propose ce médicament '
                        'pour le moment.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.only(
                      bottom: 24, left: 0, right: 0, top: 4),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 2),
                  itemBuilder: (_, i) {
                    final r = filtered[i];
                    return PharmacyResultCard(
                      result: r,
                      onTap: () => _showDetail(r),
                      onRouteTap: () => _showDetail(r, showRoute: true),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMedicineHeader(
      Medicine med, SearchResults data, BuildContext context) {
    final isSmall = Responsive.isSmall(context);
    final padH = Responsive.padH(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(padH, 12, padH, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryBlue.withValues(alpha: 0.06),
            AppColors.accentGreen.withValues(alpha: 0.04),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: isSmall ? 42 : 48,
                height: isSmall ? 42 : 48,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Icon(Icons.medication_rounded,
                    color: AppColors.primaryBlue,
                    size: isSmall ? 22 : 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      med.fullName,
                      style: AppTypography.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        fontSize: isSmall ? 14 : 17,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _prescriptionBadge(med.requiresPrescription),
                        if (med.category != null)
                          Text(
                            med.category!,
                            style:
                                AppTypography.textTheme.labelMedium?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _statBox(
            '${data.availableCount} / ${data.totalCount}',
            'pharmacies partenaires ont ce médicament en stock',
            AppColors.primaryBlue,
          ),
        ],
      ),
    );
  }

  Widget _prescriptionBadge(bool? requiresPrescription) {
    final isRequired = requiresPrescription == true;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isRequired
            ? AppColors.warning.withValues(alpha: 0.12)
            : AppColors.accentGreen.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isRequired ? 'Sur ordonnance' : 'Sans ordonnance',
        style: AppTypography.textTheme.labelSmall?.copyWith(
          color: isRequired ? AppColors.warning : AppColors.accentGreen,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _statBox(String value, String label, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.local_pharmacy_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: AppTypography.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  style: AppTypography.textTheme.labelSmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilter(String key, String label, Color? color) {
    final selected = _stockFilter == key;
    return GestureDetector(
      onTap: () => setState(() => _stockFilter = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? (color ?? AppColors.primaryBlue).withValues(alpha: 0.12)
              : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? (color ?? AppColors.primaryBlue)
                : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected
                ? (color ?? AppColors.primaryBlue)
                : AppColors.textSecondary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  List<PharmacySearchResult> _applyStockFilter(
      List<PharmacySearchResult> list) {
    switch (_stockFilter) {
      case 'available':
        return list
            .where((r) => r.stockStatus == StockStatus.available)
            .toList();
      case 'low':
        return list
            .where((r) => r.stockStatus == StockStatus.lowStock)
            .toList();
      case 'out':
        return list
            .where((r) => r.stockStatus == StockStatus.outOfStock)
            .toList();
      default:
        return list;
    }
  }

  void _showDetail(dynamic result, {bool showRoute = false}) {
    if (showRoute) {
      openPharmacyRoute(context, pharmacy: result.pharmacy);
      return;
    }
    showPharmacyDetailOverlay(
      context,
      pharmacy: result.pharmacy,
      medicine: result.medicine,
      stockStatus: result.stockStatus,
      lastStockUpdate: result.inventory?.lastUpdated,
    );
  }
}
