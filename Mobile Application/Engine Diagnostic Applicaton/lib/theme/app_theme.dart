import 'package:flutter/material.dart';

class AppColors {
  // Brand
  static const amber = Color(0xFFFFC107);
  static const amberLight = Color(0xFFFFD54F);
  static const amberDark = Color(0xFFFFA000);

  // Dark theme surfaces
  static const darkBg = Color(0xFF1A1A2E);
  static const darkSurface = Color(0xFF16213E);
  static const darkCard = Color(0xFF1E2A3A);
  static const darkCardAlt = Color(0xFF243040);

  // Status colors
  static const good = Color(0xFF4CAF50);
  static const faulty = Color(0xFFE53935);
  static const warning = Color(0xFFFF9800);
  static const unknown = Color(0xFF9E9E9E);

  // Text
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFB0BEC5);
  static const textMuted = Color(0xFF607D8B);

  // Map overlay
  static const mapOverlay = Color(0xFF0D1B2A);
}

class AppTheme {
  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.amber,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.amber,
        fontFamily: 'Poppins',
      );

  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.amber,
          brightness: Brightness.dark,
          surface: AppColors.darkSurface,
          primary: AppColors.amber,
        ),
        scaffoldBackgroundColor: AppColors.darkBg,
        fontFamily: 'Poppins',
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 32,
          ),
          titleLarge: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
          titleMedium: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
            fontSize: 16,
          ),
          bodyMedium: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
          bodySmall: TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
          ),
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: AppColors.darkSurface,
        ),
        cardTheme: CardThemeData(
          color: AppColors.darkCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
}
