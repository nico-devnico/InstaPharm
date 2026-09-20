import 'supabase_service.dart';

/// Journal d’activité applicatif (audit_logs) — best effort, jamais bloquant.
class AuditService {
  AuditService._();
  static final AuditService instance = AuditService._();

  Future<void> log({
    required String action,
    required String resourceType,
    String? resourceId,
    Map<String, dynamic>? meta,
  }) async {
    try {
      final db = SupabaseService.client;
      final uid = db.auth.currentUser?.id;
      await db.from('audit_logs').insert({
        'actor_id': uid,
        'action': action,
        'resource_type': resourceType,
        'resource_id': resourceId,
        'meta': {
          ...?meta,
          'client': 'flutter',
          'at': DateTime.now().toIso8601String(),
        },
      });
    } catch (_) {
      // Ne jamais faire échouer l’UX pour un log.
    }
  }
}
