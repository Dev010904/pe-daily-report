import 'package:flutter/material.dart';

class AppColors {
  static const navy = Color(0xFF1A4070);
  static const navyDark = Color(0xFF0E2747);
  static const gold = Color(0xFFC9962B);
  static const full = Color(0xFF1E7B45);
  static const fullBg = Color(0xFFE6F4EA);
  static const empty = Color(0xFF2B5FA8);
  static const emptyBg = Color(0xFFE5EEFA);
  static const amber = Color(0xFFB87A00);
  static const amberBg = Color(0xFFFFF3D6);
  static const amberLine = Color(0xFFE8B83A);
  static const danger = Color(0xFFC62828);
  static const page = Color(0xFFF3F5F9);
  static const line = Color(0xFFD5DBE5);
  static const muted = Color(0xFF66707F);
  static const groupAr = Color(0xFF0F8B8D);
  static const groupN2 = Color(0xFF5C4DB1);

  /// Loan cylinders (borrowed from a filling plant).
  static const loan = Color(0xFF8E24AA);
  static const loanBg = Color(0xFFF7EAFB);
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.navy,
    primary: AppColors.navy,
    surface: Colors.white,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.page,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: const Color(0xFF1B2330),
      displayColor: const Color(0xFF1B2330),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.navy,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.line),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
