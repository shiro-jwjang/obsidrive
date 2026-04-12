import 'package:flutter/material.dart';

const _fontFamilyFallback = <String>[
  'Noto Sans KR',
  'Apple SD Gothic Neo',
  'Malgun Gothic',
  'Roboto',
  'Arial',
  'sans-serif',
];

ThemeData buildLightTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF00796B),
    brightness: Brightness.light,
  ).copyWith(surface: Colors.white);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: Colors.white,
    fontFamilyFallback: _fontFamilyFallback,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF17201E),
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}

ThemeData buildDarkTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF26A69A),
    brightness: Brightness.dark,
  ).copyWith(surface: const Color(0xFF1E1F20));

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: const Color(0xFF181A1B),
    fontFamilyFallback: _fontFamilyFallback,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF181A1B),
      foregroundColor: Color(0xFFE8ECEA),
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}
