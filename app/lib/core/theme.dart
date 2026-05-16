import 'package:flutter/material.dart';

/// SolenStay 디자인 시스템 (라이트 테마)
/// 목업 mockup.html과 동일한 컬러 팔레트.
class AppColors {
  // 호점 색상
  static const branch1 = Color(0xFF3B82F6); // 1호점
  static const branch2 = Color(0xFF10B981); // 2호점
  static const branch3 = Color(0xFFF97316); // 3호점

  // 기본 톤
  static const bg = Color(0xFFF8FAFC);
  static const panel = Color(0xFFFFFFFF);
  static const panel2 = Color(0xFFF1F5F9);
  static const line = Color(0xFFE2E8F0);
  static const text = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const dim = Color(0xFF94A3B8);

  // 상태
  static const danger = Color(0xFFDC2626);
  static const warn = Color(0xFFD97706);
  static const ok = Color(0xFF16A34A);

  static Color branchColor(String branchId) {
    switch (branchId) {
      case 'branch1':
        return branch1;
      case 'branch2':
        return branch2;
      case 'branch3':
        return branch3;
      default:
        return muted;
    }
  }
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: 'Pretendard',
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.branch1,
      brightness: Brightness.light,
      primary: AppColors.branch1,
      surface: AppColors.panel,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.line),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.branch1,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.line),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: AppColors.panel,
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text),
      titleMedium: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text),
      bodyMedium: TextStyle(color: AppColors.text),
      bodySmall: TextStyle(color: AppColors.muted, fontSize: 11),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.branch1, width: 2),
      ),
    ),
  );
}
