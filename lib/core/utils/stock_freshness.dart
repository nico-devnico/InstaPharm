import '../../models/enums.dart';

/// Libellés de fraîcheur du stock, ex. « Disponible · Stock mis à jour il y a 8 min ».
class StockFreshness {
  StockFreshness._();

  static String formatTimeAgo(DateTime? when, {DateTime? now}) {
    if (when == null) return 'date inconnue';
    final diff = (now ?? DateTime.now()).difference(when);
    if (diff.inSeconds < 45) return 'à l\'instant';
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    if (diff.inDays < 7) return 'il y a ${diff.inDays} j';
    return 'il y a ${(diff.inDays / 7).floor()} sem';
  }

  /// Ne présente jamais UNKNOWN comme Disponible.
  static String label({
    required StockStatus status,
    DateTime? lastUpdated,
    bool includeStatus = true,
  }) {
    final statusPart = status.displayName;
    if (lastUpdated == null) {
      return includeStatus ? statusPart : 'Stock non daté';
    }
    final ago = formatTimeAgo(lastUpdated);
    if (!includeStatus) return 'Stock mis à jour $ago';
    return '$statusPart · Stock mis à jour $ago';
  }

  static bool isStale(
    DateTime? lastUpdated, {
    StockSource source = StockSource.manual,
    Duration manualTtl = const Duration(hours: 24),
    Duration syncTtl = const Duration(hours: 6),
    DateTime? lastSyncedAt,
  }) {
    final now = DateTime.now();
    if (source == StockSource.manual) {
      if (lastUpdated == null) return true;
      return now.difference(lastUpdated) > manualTtl;
    }
    final sync = lastSyncedAt ?? lastUpdated;
    if (sync == null) return true;
    return now.difference(sync) > syncTtl;
  }
}
