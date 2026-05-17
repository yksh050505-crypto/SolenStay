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

/// Pretendard 웹폰트 (CDN에서 index.html로 로드)
const _fontFamily = 'Pretendard Variable';
const _fontFallback = <String>['Pretendard', 'Noto Sans KR', 'sans-serif'];

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallback,
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
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
        fontWeight: FontWeight.w600,
        fontSize: 16,
        color: AppColors.text,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.branch1,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: TextStyle(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.line),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: AppColors.panel,
        textStyle: TextStyle(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        elevation: 0,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.branch1,
        textStyle: TextStyle(
          fontFamily: _fontFamily,
          fontFamilyFallback: _fontFallback,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: TextStyle(
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
        fontWeight: FontWeight.w700,
        fontSize: 18,
        color: AppColors.text,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    textTheme: TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text, fontFamily: _fontFamily, fontFamilyFallback: _fontFallback),
      titleMedium: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text, fontFamily: _fontFamily, fontFamilyFallback: _fontFallback),
      titleSmall: TextStyle(fontWeight: FontWeight.w600, color: AppColors.text, fontFamily: _fontFamily, fontFamilyFallback: _fontFallback, fontSize: 14),
      bodyMedium: TextStyle(color: AppColors.text, fontFamily: _fontFamily, fontFamilyFallback: _fontFallback),
      bodySmall: TextStyle(color: AppColors.muted, fontSize: 12, fontFamily: _fontFamily, fontFamilyFallback: _fontFallback),
      labelSmall: TextStyle(color: AppColors.muted, fontSize: 11, fontFamily: _fontFamily, fontFamilyFallback: _fontFallback),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(color: AppColors.dim, fontSize: 13),
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.line,
      thickness: 1,
      space: 0,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
  );
}
