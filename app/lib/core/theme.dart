import 'package:flutter/material.dart';

/// 화면별로 변하는 표면 색을 라이트/다크에서 자동 분기.
/// 사용: `context.brand.text` / `context.brand.bg` 등
class BrandColors extends ThemeExtension<BrandColors> {
  final Color bg;
  final Color panel;
  final Color panel2;
  final Color line;
  final Color text;
  final Color muted;
  final Color dim;

  const BrandColors({
    required this.bg,
    required this.panel,
    required this.panel2,
    required this.line,
    required this.text,
    required this.muted,
    required this.dim,
  });

  static const light = BrandColors(
    bg: Color(0xFFF8FAFC),
    panel: Color(0xFFFFFFFF),
    panel2: Color(0xFFF1F5F9),
    line: Color(0xFFE2E8F0),
    text: Color(0xFF0F172A),
    muted: Color(0xFF64748B),
    dim: Color(0xFF94A3B8),
  );

  static const dark = BrandColors(
    bg: Color(0xFF0B1220),
    panel: Color(0xFF111827),
    panel2: Color(0xFF1E293B),
    line: Color(0xFF1F2937),
    text: Color(0xFFE2E8F0),
    muted: Color(0xFF94A3B8),
    dim: Color(0xFF64748B),
  );

  @override
  BrandColors copyWith({
    Color? bg,
    Color? panel,
    Color? panel2,
    Color? line,
    Color? text,
    Color? muted,
    Color? dim,
  }) =>
      BrandColors(
        bg: bg ?? this.bg,
        panel: panel ?? this.panel,
        panel2: panel2 ?? this.panel2,
        line: line ?? this.line,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        dim: dim ?? this.dim,
      );

  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) {
    if (other is! BrandColors) return this;
    return BrandColors(
      bg: Color.lerp(bg, other.bg, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      panel2: Color.lerp(panel2, other.panel2, t)!,
      line: Color.lerp(line, other.line, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      dim: Color.lerp(dim, other.dim, t)!,
    );
  }
}

extension BrandColorsX on BuildContext {
  BrandColors get brand =>
      Theme.of(this).extension<BrandColors>() ?? BrandColors.light;
}

/// SolenStay 디자인 시스템
///
/// - 호점 색(branch1/2/3) + 상태 색(ok/warn/danger)은 라이트/다크 동일
/// - surface 계열(bg/panel/panel2/line/text/muted/dim) 정적 값은 라이트 기본.
///   다크모드에서 Material 자동 적응되는 곳(Scaffold, Card, AppBar, TextField, Dialog 등)은
///   ThemeData의 darkTheme이 자동으로 처리. 일부 hardcoded Container 색은 라이트 톤 유지.
class AppColors {
  // ── 호점 색 — 차가운 톤 3색 분리 (구분 명확)
  static const branch1 = Color(0xFF2563EB); // 1호점 — 파랑
  static const branch2 = Color(0xFF0EA5E9); // 2호점 — 청록
  static const branch3 = Color(0xFF8B5CF6); // 3호점 — 보라

  /// 호점 짧은 라벨 — pill 좌측 표시용 ("1호", "2호", "3호")
  static String branchShortLabel(String branchId) {
    switch (branchId) {
      case 'branch1':
        return '1호';
      case 'branch2':
        return '2호';
      case 'branch3':
        return '3호';
      default:
        return '';
    }
  }

  // ── 기본 톤 (라이트)
  static const bg = Color(0xFFF8FAFC);
  static const panel = Color(0xFFFFFFFF);
  static const panel2 = Color(0xFFF1F5F9);
  static const line = Color(0xFFE2E8F0);
  static const text = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const dim = Color(0xFF94A3B8);

  // ── 상태 (라이트/다크 공통)
  static const danger = Color(0xFFDC2626);
  static const warn = Color(0xFFD97706);
  static const ok = Color(0xFF16A34A);

  // ── 다크 surface 톤 (ThemeData.darkTheme 에서 사용)
  static const bgDark = Color(0xFF0B1220);
  static const panelDark = Color(0xFF111827);
  static const panel2Dark = Color(0xFF1E293B);
  static const lineDark = Color(0xFF1F2937);
  static const textDark = Color(0xFFE2E8F0);
  static const mutedDark = Color(0xFF94A3B8);
  static const dimDark = Color(0xFF64748B);

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

const _fontFamily = 'Pretendard Variable';
const _fontFallback = <String>['Pretendard', 'Noto Sans KR', 'sans-serif'];

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.bg,
    extensions: const <ThemeExtension<dynamic>>[BrandColors.light],
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
      contentTextStyle: TextStyle(
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
        fontSize: 14,
        color: AppColors.text,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentTextStyle: TextStyle(
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
        fontSize: 13,
        color: Colors.white,
      ),
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
      hintStyle: TextStyle(
        color: AppColors.dim,
        fontSize: 13,
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      ),
      labelStyle: TextStyle(
        color: AppColors.muted,
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      ),
      floatingLabelStyle: TextStyle(
        color: AppColors.branch1,
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      ),
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

/// 다크 테마 — Material3 자동 적응 + brand color 유지.
/// 직접 AppColors.bg/panel/text 등 hardcode 된 곳은 라이트 톤으로 남을 수 있음(점진적 마이그레이션).
ThemeData buildDarkAppTheme() {
  const seed = AppColors.branch1;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bgDark,
    extensions: const <ThemeExtension<dynamic>>[BrandColors.dark],
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallback,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      primary: seed,
      surface: AppColors.panelDark,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: AppColors.panelDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.lineDark),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bgDark,
      foregroundColor: AppColors.textDark,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
        fontWeight: FontWeight.w600,
        fontSize: 16,
        color: AppColors.textDark,
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
        foregroundColor: AppColors.textDark,
        side: const BorderSide(color: AppColors.lineDark),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: AppColors.panelDark,
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
      backgroundColor: AppColors.panelDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titleTextStyle: TextStyle(
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
        fontWeight: FontWeight.w700,
        fontSize: 18,
        color: AppColors.textDark,
      ),
      contentTextStyle: TextStyle(
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
        fontSize: 14,
        color: AppColors.textDark,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      contentTextStyle: TextStyle(
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
        fontSize: 13,
        color: Colors.white,
      ),
    ),
    textTheme: TextTheme(
      headlineSmall: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textDark, fontFamily: _fontFamily, fontFamilyFallback: _fontFallback),
      titleMedium: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark, fontFamily: _fontFamily, fontFamilyFallback: _fontFallback),
      titleSmall: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textDark, fontFamily: _fontFamily, fontFamilyFallback: _fontFallback, fontSize: 14),
      bodyMedium: TextStyle(color: AppColors.textDark, fontFamily: _fontFamily, fontFamilyFallback: _fontFallback),
      bodySmall: TextStyle(color: AppColors.mutedDark, fontSize: 12, fontFamily: _fontFamily, fontFamilyFallback: _fontFallback),
      labelSmall: TextStyle(color: AppColors.mutedDark, fontSize: 11, fontFamily: _fontFamily, fontFamilyFallback: _fontFallback),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.panel2Dark,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(
        color: AppColors.dimDark,
        fontSize: 13,
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      ),
      labelStyle: TextStyle(
        color: AppColors.mutedDark,
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      ),
      floatingLabelStyle: TextStyle(
        color: AppColors.branch1,
        fontFamily: _fontFamily,
        fontFamilyFallback: _fontFallback,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.lineDark),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.lineDark),
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
      color: AppColors.lineDark,
      thickness: 1,
      space: 0,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.panelDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
  );
}
