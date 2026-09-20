import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // ── Couleur principale ─────────────────────────────────────────
  // Bleu électrique moderne (Indigo-600)
  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color primaryBlueLight = Color(0xFF60A5FA);
  static const Color primaryBlueDark = Color(0xFF1D4ED8);

  // Gradient principal
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2563EB), Color(0xFF4F46E5)],
  );

  // Gradient card hero
  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
  );

  // ── Accent ────────────────────────────────────────────────────
  static const Color accentGreen = Color(0xFF10B981);
  static const Color accentGreenLight = Color(0xFF34D399);
  static const Color accentGreenDark = Color(0xFF059669);

  static const Color accentPurple = Color(0xFF8B5CF6);
  static const Color accentOrange = Color(0xFFF97316);

  // ── Surfaces (Slate moderne) ───────────────────────────────────
  static const Color background = Color(0xFFF8FAFC);   // Slate-50
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF1F5F9); // Slate-100
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  // ── Texte ─────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF0F172A);   // Slate-900
  static const Color textSecondary = Color(0xFF475569); // Slate-600
  static const Color textTertiary = Color(0xFF94A3B8);  // Slate-400

  // ── Bordures ──────────────────────────────────────────────────
  static const Color border = Color(0xFFE2E8F0);        // Slate-200
  static const Color divider = Color(0xFFF1F5F9);       // Slate-100

  // ── Statut stocks ─────────────────────────────────────────────
  static const Color available = Color(0xFF10B981);
  static const Color lowStock = Color(0xFFF59E0B);
  static const Color outOfStock = Color(0xFFEF4444);
  static const Color unknown = Color(0xFF94A3B8);

  // ── Statut pharmacie ──────────────────────────────────────────
  static const Color open = Color(0xFF10B981);
  static const Color closed = Color(0xFFEF4444);
  static const Color duty = Color(0xFF8B5CF6);

  // ── Sémantique ────────────────────────────────────────────────
  static const Color error = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);
  static const Color success = Color(0xFF10B981);
  static const Color info = Color(0xFF3B82F6);

  // ── Ombres ────────────────────────────────────────────────────
  static const Color shadow = Color(0x0A000000);
  static const Color shadowMedium = Color(0x14000000);
  static const Color shadowStrong = Color(0x1F000000);

  // ── Helpers ombres stylisées ──────────────────────────────────
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFF2563EB).withValues(alpha: 0.05),
          blurRadius: 20,
          offset: const Offset(0, 4),
          spreadRadius: 0,
        ),
        const BoxShadow(
          color: Color(0x08000000),
          blurRadius: 8,
          offset: Offset(0, 2),
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get elevatedShadow => [
        BoxShadow(
          color: const Color(0xFF2563EB).withValues(alpha: 0.12),
          blurRadius: 32,
          offset: const Offset(0, 8),
          spreadRadius: -4,
        ),
        const BoxShadow(
          color: Color(0x0F000000),
          blurRadius: 16,
          offset: Offset(0, 4),
          spreadRadius: 0,
        ),
      ];

  static List<BoxShadow> get navShadow => [
        const BoxShadow(
          color: Color(0x12000000),
          blurRadius: 24,
          offset: Offset(0, -4),
          spreadRadius: 0,
        ),
      ];
}
