import 'package:flutter/material.dart';

ThemeData wealthMateTheme() {
  const forest = Color(0xFF12201D);
  const mint = Color(0xFFBDEBDC);
  const cream = Color(0xFFFBFCFA);
  final scheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F9F7D), brightness: Brightness.light)
      .copyWith(
    primary: forest,
    onPrimary: Colors.white,
    secondary: const Color(0xFF2F9F7D),
    surface: Colors.white,
    onSurface: const Color(0xFF1A2621),
    tertiary: const Color(0xFF6A6CF4),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: cream,
    appBarTheme: const AppBarTheme(
      backgroundColor: cream,
      foregroundColor: forest,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2EAE5))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2EAE5))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: mint, width: 2)),
    ),
    navigationBarTheme: const NavigationBarThemeData(indicatorColor: mint),
    navigationRailTheme: const NavigationRailThemeData(
        selectedIconTheme: IconThemeData(color: forest),
        selectedLabelTextStyle:
            TextStyle(color: forest, fontWeight: FontWeight.w700)),
  );
}
