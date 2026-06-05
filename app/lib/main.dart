import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'core/theme.dart';
import 'app_router.dart';
import 'data/services.dart';

/// SharedPreferences 키 — 디바이스별 자동 로그인 설정 (기본 false = 매번 로그인)
const String kPrefAutoLogin = 'auto_login_enabled';

/// SharedPreferences 키 — 테마 모드 ('system' | 'light' | 'dark')
const String kPrefThemeMode = 'theme_mode';

ThemeMode _parseThemeMode(String? raw) {
  switch (raw) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

String themeModeToString(ThemeMode m) {
  switch (m) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    case ThemeMode.system:
      return 'system';
  }
}

/// 전역 ThemeMode — SharedPreferences로 영구 저장.
/// 초기값은 main()에서 prefs 읽어 overrideWith.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR', null);
  await initializeDateFormatting('en_US', null);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // SharedPreferences에서 자동로그인·테마모드 로드
  ThemeMode initialMode = ThemeMode.system;
  try {
    final prefs = await SharedPreferences.getInstance();
    final autoLogin = prefs.getBool(kPrefAutoLogin) ?? false;
    if (!autoLogin) {
      await FirebaseAuth.instance.signOut();
    }
    initialMode = _parseThemeMode(prefs.getString(kPrefThemeMode));
  } catch (_) {}

  runApp(ProviderScope(
    overrides: [
      themeModeProvider.overrideWith((ref) => initialMode),
    ],
    child: const SolenStayApp(),
  ));
}

class SolenStayApp extends ConsumerWidget {
  const SolenStayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'SolenStay',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildDarkAppTheme(),
      themeMode: themeMode,
      routerConfig: router,
      locale: locale,
      supportedLocales: const [Locale('ko'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
