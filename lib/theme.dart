import 'package:flutter/material.dart';

/// One selectable colour theme.
class KPalette {
  final String id;
  final String name;
  final bool dark;
  final Color bg, panel, panel2, line, txt, muted, accent;
  const KPalette({
    required this.id,
    required this.name,
    required this.dark,
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.line,
    required this.txt,
    required this.muted,
    required this.accent,
  });
}

/// Runtime-switchable palette. Every screen reads these getters, so changing
/// [SV.current] and rebuilding re-themes the whole app.
class SV {
  static const List<KPalette> palettes = [
    KPalette(
      id: 'midnight', name: 'Midnight Blue', dark: true,
      bg: Color(0xFF0B0F17), panel: Color(0xFF131A26),
      panel2: Color(0xFF0F1520), line: Color(0xFF243044),
      txt: Color(0xFFE7EDF5), muted: Color(0xFF93A1B5),
      accent: Color(0xFF4F8CFF),
    ),
    KPalette(
      id: 'amoled', name: 'Pure Black', dark: true,
      bg: Color(0xFF000000), panel: Color(0xFF0E0E10),
      panel2: Color(0xFF17171A), line: Color(0xFF26262B),
      txt: Color(0xFFF2F2F2), muted: Color(0xFF9A9AA2),
      accent: Color(0xFF3D8BFF),
    ),
    KPalette(
      id: 'crimson', name: 'Black & Red', dark: true,
      bg: Color(0xFF0A0A0C), panel: Color(0xFF151518),
      panel2: Color(0xFF1C1C20), line: Color(0xFF2A2A30),
      txt: Color(0xFFF2F2F2), muted: Color(0xFF9E9EA6),
      accent: Color(0xFFE53935),
    ),
    KPalette(
      id: 'light', name: 'Clean White', dark: false,
      bg: Color(0xFFF4F6FB), panel: Color(0xFFFFFFFF),
      panel2: Color(0xFFEDF1F7), line: Color(0xFFD9E1EE),
      txt: Color(0xFF1A2230), muted: Color(0xFF66748C),
      accent: Color(0xFF2B64D6),
    ),
    KPalette(
      id: 'light_red', name: 'White & Red', dark: false,
      bg: Color(0xFFFAF6F6), panel: Color(0xFFFFFFFF),
      panel2: Color(0xFFF4ECEC), line: Color(0xFFE8DADA),
      txt: Color(0xFF221A1A), muted: Color(0xFF7D6B6B),
      accent: Color(0xFFD32F2F),
    ),
    KPalette(
      id: 'ocean', name: 'Ocean Teal', dark: true,
      bg: Color(0xFF07151A), panel: Color(0xFF0D2027),
      panel2: Color(0xFF102830), line: Color(0xFF1D3A44),
      txt: Color(0xFFE3F2F5), muted: Color(0xFF8FB3BC),
      accent: Color(0xFF00BCD4),
    ),
    KPalette(
      id: 'royal', name: 'Royal Purple', dark: true,
      bg: Color(0xFF0F0B1A), panel: Color(0xFF1A1428),
      panel2: Color(0xFF211A33), line: Color(0xFF2F2647),
      txt: Color(0xFFEEE9F8), muted: Color(0xFFA59DBB),
      accent: Color(0xFF8B5CF6),
    ),
    KPalette(
      id: 'emerald', name: 'Emerald', dark: true,
      bg: Color(0xFF07130E), panel: Color(0xFF0E2018),
      panel2: Color(0xFF12291F), line: Color(0xFF1E3D2F),
      txt: Color(0xFFE4F3EC), muted: Color(0xFF8FB5A3),
      accent: Color(0xFF22C55E),
    ),
    KPalette(
      id: 'sunset', name: 'Sunset Orange', dark: true,
      bg: Color(0xFF140D0A), panel: Color(0xFF21150F),
      panel2: Color(0xFF2A1B13), line: Color(0xFF3A281E),
      txt: Color(0xFFF6ECE6), muted: Color(0xFFB8A195),
      accent: Color(0xFFFF7A45),
    ),
    KPalette(
      id: 'rose', name: 'Rose Pink', dark: true,
      bg: Color(0xFF16090F), panel: Color(0xFF231019),
      panel2: Color(0xFF2B1420), line: Color(0xFF3F2030),
      txt: Color(0xFFF8E9F0), muted: Color(0xFFBC98A9),
      accent: Color(0xFFF472B6),
    ),
    KPalette(
      id: 'gold', name: 'Black Gold', dark: true,
      bg: Color(0xFF0C0A06), panel: Color(0xFF17140C),
      panel2: Color(0xFF1E1A10), line: Color(0xFF2F2918),
      txt: Color(0xFFF6F0E1), muted: Color(0xFFB3A781),
      accent: Color(0xFFEAB308),
    ),
    KPalette(
      id: 'slate', name: 'Graphite', dark: true,
      bg: Color(0xFF111315), panel: Color(0xFF1B1E21),
      panel2: Color(0xFF22262A), line: Color(0xFF33383E),
      txt: Color(0xFFEDEFF1), muted: Color(0xFF9AA1A9),
      accent: Color(0xFF94A3B8),
    ),
    KPalette(
      id: 'light_green', name: 'Mint Light', dark: false,
      bg: Color(0xFFF2FAF6), panel: Color(0xFFFFFFFF),
      panel2: Color(0xFFE6F4ED), line: Color(0xFFCFE6DA),
      txt: Color(0xFF15261E), muted: Color(0xFF5E7A6C),
      accent: Color(0xFF059669),
    ),
    KPalette(
      id: 'light_purple', name: 'Lavender Light', dark: false,
      bg: Color(0xFFF7F5FD), panel: Color(0xFFFFFFFF),
      panel2: Color(0xFFEEEAFB), line: Color(0xFFDDD6F3),
      txt: Color(0xFF1E1A2E), muted: Color(0xFF6E6889),
      accent: Color(0xFF7C3AED),
    ),
    KPalette(
      id: 'sky', name: 'Sky Light', dark: false,
      bg: Color(0xFFF1F8FD), panel: Color(0xFFFFFFFF),
      panel2: Color(0xFFE3F1FB), line: Color(0xFFC9E2F3),
      txt: Color(0xFF0F2433), muted: Color(0xFF5A7487),
      accent: Color(0xFF0284C7),
    ),
  ];

  static KPalette current = palettes.first;

  static void setTheme(String id) {
    current = palettes.firstWhere((p) => p.id == id,
        orElse: () => palettes.first);
  }

  static bool get dark => current.dark;
  static Color get bg => current.bg;
  static Color get panel => current.panel;
  static Color get panel2 => current.panel2;
  static Color get line => current.line;
  static Color get txt => current.txt;
  static Color get muted => current.muted;
  static Color get accent => current.accent;
  static Color get accent2 => current.accent;
  static Color get ok => const Color(0xFF2ECC71);
  static Color get warn => const Color(0xFFF5A623);
  static Color get bad => const Color(0xFFFF5C6C);
  static Color get fair => const Color(0xFFE0A800);
}

ThemeData buildTheme() {
  final base = SV.dark ? ThemeData.dark(useMaterial3: true)
                       : ThemeData.light(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: SV.bg,
    colorScheme: base.colorScheme.copyWith(
      brightness: SV.dark ? Brightness.dark : Brightness.light,
      primary: SV.accent,
      secondary: SV.accent,
      surface: SV.panel,
      error: SV.bad,
    ),
    cardColor: SV.panel,
    dividerColor: SV.line,
    appBarTheme: AppBarTheme(
      backgroundColor: SV.bg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      foregroundColor: SV.txt,
      titleTextStyle: TextStyle(
        color: SV.txt,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: SV.panel,
      indicatorColor: SV.accent.withValues(alpha: 0.18),
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? SV.accent
              : SV.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? SV.accent : SV.muted,
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: SV.panel2,
      contentTextStyle: TextStyle(color: SV.txt),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: SV.accent,
      foregroundColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: SV.panel2,
      hintStyle: TextStyle(color: SV.muted),
      labelStyle: TextStyle(color: SV.muted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: SV.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: SV.accent),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: SV.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: CardThemeData(
      color: SV.panel,
      elevation: SV.dark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: SV.line),
      ),
    ),
    textTheme: base.textTheme.apply(bodyColor: SV.txt, displayColor: SV.txt),
  );
}
