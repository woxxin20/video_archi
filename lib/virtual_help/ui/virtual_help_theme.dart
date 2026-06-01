import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for the Virtual Help module.
/// Edit this file to restyle the entire module.
class VirtualHelpTheme {
  VirtualHelpTheme._();

  // ── Brand colors ──────────────────────────────────────────────────
  static const Color brand = Color(0xFFFF8735);
  static const Color brandSoft = Color(0xFFFFB07A);
  static const Color brandXs = Color(0x1AFF8735);

  // ── Background palette ────────────────────────────────────────────
  static const Color bgWarm = Color(0xFFFDF7F2);
  static const Color bgWhite = Color(0xFFFFFFFF);
  static const Color bgMuted = Color(0xFFF5EDE3);

  // ── Text palette ──────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF1A1208);
  static const Color textSecondary = Color(0xFF6B5B4E);
  static const Color textMuted = Color(0xFFA8907E);

  // ── Border ────────────────────────────────────────────────────────
  static const Color border = Color(0x121A1208);
  static const Color borderBrand = Color(0x38FF8735);

  // ── Dark player bg ────────────────────────────────────────────────
  static const Color playerBg = Color(0xFF0D0A07);

  // ── Category accent colors ─────────────────────────────────────────
  static const Map<String, Color> categoryAccent = {
    'tips': brand,
    'avoid': Color(0xFF46ABDF),
    'awareness': Color(0xFF35B76A),
  };

  // ── Category display labels ────────────────────────────────────────
  static const Map<String, String> categoryLabel = {
    'tips': 'Tips',
    'avoid': 'Avoid',
    'awareness': 'Be Aware',
  };

  // ── Category gradients (for cards without a thumbnail) ────────────
  static const Map<String, List<Color>> categoryGradient = {
    'tips': [Color(0xFFFFDCB8), Color(0xFFFF8C42)],
    'avoid': [Color(0xFFBDE8FF), Color(0xFF46ABDF)],
    'awareness': [Color(0xFFC6F5D8), Color(0xFF35B76A)],
  };

  // ── Typography helpers ─────────────────────────────────────────────
  static TextStyle serif({
    double size = 14,
    FontWeight weight = FontWeight.w200,
    Color color = textPrimary,
    bool italic = false,
    double? letterSpacing,
  }) {
    return GoogleFonts.fraunces(
      fontSize: size,
      fontWeight: weight,
      color: color,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle sans({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color color = textPrimary,
    double? letterSpacing,
    double? height,
  }) {
    return GoogleFonts.plusJakartaSans(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  // ── Card dimensions ────────────────────────────────────────────────
  static const double cardWidth = 128;
  static const double cardThumbnailHeight = 210;
  static const double cardBorderRadius = 16;

  // ── Player overlay constants ───────────────────────────────────────
  static const double playerTopPadding = 60;
}
