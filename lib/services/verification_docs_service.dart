import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class PickedVerificationDoc {
  final String fileName;
  final List<int> bytes;
  final String contentType;

  const PickedVerificationDoc({
    required this.fileName,
    required this.bytes,
    required this.contentType,
  });
}

/// Sélection + upload des pièces d’identité (image / PDF).
class VerificationDocsService {
  VerificationDocsService._();
  static final VerificationDocsService instance = VerificationDocsService._();

  SupabaseClient get _db => SupabaseService.client;

  static const _allowedExt = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'pdf'};

  /// Ouvre le sélecteur natif. Retourne null si annulé.
  /// Ne lève jamais sans message : [onError] reçoit le détail.
  Future<PickedVerificationDoc?> pickDocument({
    void Function(String message)? onError,
  }) async {
    try {
      var files = await FilePicker.pickFiles(
        dialogTitle: 'Choisir un document (image ou PDF)',
        type: FileType.custom,
        allowedExtensions: _allowedExt.toList(),
      );

      // Fallback : certains OS ignorent FileType.custom
      if (files.isEmpty) {
        files = await FilePicker.pickFiles(
          dialogTitle: 'Choisir un fichier',
          type: FileType.any,
        );
      }

      if (files.isEmpty) return null;

      final file = files.first;
      final name = file.name;
      final ext = (file.extension ?? _extOf(name)).toLowerCase();
      if (!_allowedExt.contains(ext)) {
        onError?.call(
          'Format non accepté (.$ext). Utilisez JPG, PNG, WEBP, GIF ou PDF.',
        );
        return null;
      }

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        onError?.call('Fichier vide ou illisible.');
        return null;
      }
      if (bytes.length > 10 * 1024 * 1024) {
        onError?.call('Fichier trop volumineux (max 10 Mo).');
        return null;
      }

      return PickedVerificationDoc(
        fileName: name,
        bytes: bytes,
        contentType: _contentType(ext),
      );
    } catch (e, st) {
      debugPrint('VerificationDocsService.pickDocument: $e\n$st');
      onError?.call('Impossible d’ouvrir le sélecteur de fichiers : $e');
      return null;
    }
  }

  /// Upload vers le bucket `verification-docs`.
  /// [folder] = userId (candidat) ou applicationId (admin).
  Future<String> upload({
    required String folder,
    required PickedVerificationDoc doc,
  }) async {
    final safeName = doc.fileName.replaceAll(RegExp(r'[^\w.\-]+'), '_');
    final path =
        '$folder/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final data = doc.bytes is Uint8List
        ? doc.bytes as Uint8List
        : Uint8List.fromList(doc.bytes);

    try {
      await _db.storage.from('verification-docs').uploadBinary(
            path,
            data,
            fileOptions: FileOptions(
              contentType: doc.contentType,
              upsert: true,
            ),
          );
    } on StorageException catch (e) {
      // Bucket absent → message actionnable
      throw Exception(
        e.message.contains('Bucket') || e.statusCode == '404'
            ? 'Bucket « verification-docs » manquant. '
                'Exécutez supabase/verification_docs_storage.sql'
            : 'Upload refusé : ${e.message}',
      );
    }

    return _db.storage.from('verification-docs').getPublicUrl(path);
  }

  Future<void> attachToApplication({
    required String applicationId,
    String? idDocumentUrl,
    String? professionalDocumentUrl,
    String? licenseNumber,
    String? notes,
  }) async {
    final patch = <String, dynamic>{
      if (idDocumentUrl != null) 'id_document_url': idDocumentUrl,
      if (professionalDocumentUrl != null)
        'professional_document_url': professionalDocumentUrl,
      if (licenseNumber != null) 'license_number': licenseNumber,
      if (notes != null) 'notes': notes,
      'updated_at': DateTime.now().toIso8601String(),
    };
    await _db
        .from('account_applications')
        .update(patch)
        .eq('id', applicationId);
  }

  Future<Map<String, dynamic>?> myLatestApplication() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    final row = await _db
        .from('account_applications')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return Map<String, dynamic>.from(row);
  }

  static String _extOf(String name) {
    final i = name.lastIndexOf('.');
    if (i < 0 || i == name.length - 1) return '';
    return name.substring(i + 1);
  }

  static String _contentType(String ext) {
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/jpeg';
    }
  }
}
