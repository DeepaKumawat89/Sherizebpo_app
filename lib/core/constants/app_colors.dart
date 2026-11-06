import 'package:flutter/material.dart';

/// Premium design system color palette for Human Cold BPO.
///
/// Refined from a modern SaaS-grade aesthetic with deep blues,
/// soft neutrals, and vibrant semantic colors.
///
/// Usage: `AppColors.primary` or `AppColors.textDark`.
class AppColors {
  AppColors._();

  // ─── Brand ──────────────────────────────────────────────────
  static const Color primary = Color(0xFF6366F1); // Indigo 500  — Vibrant trust
  static const Color primaryDark =
      Color(0xFF4F46E5); // Indigo 600  — Hover/Active
  static const Color primaryLight =
      Color(0xFF818CF8); // Indigo 400  — Soft accents
  static const Color primarySoft =
      Color(0xFFEEF2FF); // Indigo 50   — Tinted backgrounds
  static const Color primaryMuted =
      Color(0xFFC7D2FE); // Indigo 200  — Light borders

  static const Color secondary = Color(0xFF0F172A); // Slate 900   — Dark mode
  static const Color secondaryLight =
      Color(0xFF1E293B); // Slate 800   — Dark cards

  // ─── Accents ────────────────────────────────────────────────
  static const Color accent = Color(0xFFF59E0B); // Amber 500   — Highlights
  static const Color accentLight = Color(0xFFFBBF24); // Amber 400
  static const Color accentSoft = Color(0xFFFEF3C7); // Amber 100

  static const Color teal = Color(0xFF14B8A6); // Teal 500    — Secondary accent
  static const Color tealSoft = Color(0xFFCCFBF1); // Teal 100

  static const Color violet = Color(0xFF8B5CF6); // Violet 500  — Premium accent
  static const Color violetSoft = Color(0xFFEDE9FE); // Violet 100

  static const Color rose = Color(0xFFF43F5E); // Rose 500
  static const Color roseSoft = Color(0xFFFFF1F2); // Rose 50

  // ─── Backgrounds ────────────────────────────────────────────
  static const Color background = Color(0xFFF8FAFC); // Slate 50    — Page bg
  static const Color surface = Color(0xFFFFFFFF); // White       — Cards
  static const Color surfaceVariant =
      Color(0xFFF1F5F9); // Slate 100   — Inputs/Subtle
  static const Color surfaceElevated =
      Color(0xFFF8FAFC); // Slate 50    — Elevated surfaces

  // ─── Text ───────────────────────────────────────────────────
  static const Color textDark = Color(0xFF0F172A); // Slate 900   — Headings
  static const Color textBody = Color(0xFF334155); // Slate 700   — Body text
  static const Color textLabel = Color(0xFF475569); // Slate 600   — Labels
  static const Color textMuted = Color(0xFF64748B); // Slate 500   — Captions
  static const Color textPlaceholder =
      Color(0xFF94A3B8); // Slate 400  — Placeholders
  static const Color textLight = Color(0xFFCBD5E1); // Slate 300   — Disabled
  static const Color textLightest = Color(0xFFF8FAFC); // Slate 50    — On dark
  static const Color textTitle = Color(0xFF0F172A); // Slate 900 — Headings (Legacy)

  // ─── Borders & Dividers ─────────────────────────────────────
  static const Color border = Color(0xFFE2E8F0); // Slate 200
  static const Color borderLight = Color(0xFFF1F5F9); // Slate 100
  static const Color borderFocus = Color(0xFF6366F1); // Indigo 500
  static const Color divider = Color(0xFFE2E8F0); // Slate 200

  // ─── Semantic ───────────────────────────────────────────────
  static const Color success = Color(0xFF10B981); // Emerald 500 — Brighter
  static const Color successBg = Color(0xFFECFDF5); // Emerald 50
  static const Color successDark = Color(0xFF059669); // Emerald 600
  static const Color successLight = Color(0xFF34D399); // Emerald 400 — For dark mode

  static const Color warning = Color(0xFFF59E0B); // Amber 500
  static const Color warningBg = Color(0xFFFEF3C7); // Amber 100
  static const Color warningDark = Color(0xFFD97706); // Amber 600
  static const Color warningLight = Color(0xFFFBBF24); // Amber 400 — For dark mode

  static const Color error = Color(0xFFEF4444); // Red 500    — Brighter
  static const Color errorBg = Color(0xFFFEF2F2); // Red 50
  static const Color errorDark = Color(0xFFDC2626); // Red 600
  static const Color errorLight = Color(0xFFF87171); // Red 400     — For dark mode

  static const Color info = Color(0xFF3B82F6); // Blue 500
  static const Color infoBg = Color(0xFFEFF6FF); // Blue 50
  static const Color infoDark = Color(0xFF2563EB); // Blue 600
  static const Color infoLight = Color(0xFF60A5FA); // Blue 400     — For dark mode

  // ─── Navigation ─────────────────────────────────────────────
  static const Color navActive = Color(0xFF6366F1); // Indigo 500
  static const Color navInactive = Color(0xFF94A3B8); // Slate 400

  // ─── Glassmorphism ──────────────────────────────────────────
  static const Color glass = Color(0x80FFFFFF); // Semi-transparent white
  static const Color glassBorder = Color(0x30FFFFFF); // Glass border
}
