import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../services/verification_docs_service.dart';

/// Bouton fiable pour déposer une pièce (image / PDF).
class DocumentDropButton extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool uploading;
  final bool done;
  final String? fileLabel;
  final VoidCallback? onPressed;

  const DocumentDropButton({
    super.key,
    required this.title,
    required this.subtitle,
    this.uploading = false,
    this.done = false,
    this.fileLabel,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: done
          ? AppColors.accentGreen.withValues(alpha: 0.08)
          : AppColors.surfaceVariant,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: uploading ? null : onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: done ? AppColors.accentGreen : AppColors.border,
              width: done ? 1.5 : 1,
            ),
          ),
          child: uploading
              ? const SizedBox(
                  height: 64,
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  children: [
                    Icon(
                      done
                          ? Icons.check_circle_rounded
                          : Icons.upload_file_rounded,
                      size: 30,
                      color: done
                          ? AppColors.accentGreen
                          : AppColors.primaryBlue,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      done ? (fileLabel ?? 'Document déposé') : subtitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: done
                            ? AppColors.accentGreen
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: uploading ? null : onPressed,
                      icon: const Icon(Icons.attach_file_rounded, size: 18),
                      label: Text(done ? 'Remplacer' : 'Choisir un fichier'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Helper UI : pick + upload + snackbars.
Future<String?> pickAndUploadVerificationDoc(
  BuildContext context, {
  required String folder,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final picked = await VerificationDocsService.instance.pickDocument(
    onError: (msg) {
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    },
  );
  if (picked == null) return null;
  try {
    final url = await VerificationDocsService.instance.upload(
      folder: folder,
      doc: picked,
    );
    messenger.showSnackBar(
      SnackBar(content: Text('Document « ${picked.fileName} » envoyé')),
    );
    return url;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
    return null;
  }
}
