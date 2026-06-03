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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR', null);
  await initializeDateFormatting('en_US', null);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // 자동 로그인이 꺼져 있으면(기본) 앱 시작 시 강제 로그아웃 → 항상 PIN 로그인부터.
  // 사용자가 내정보에서 켜면 다음 시작 시 세션 유지(자동 로그인).
  try {
    final prefs = await SharedPreferences.getInstance();
    final autoLogin = prefs.getBool(kPrefAutoLogin) ?? false;
    if (!autoLogin) {
      await FirebaseAuth.instance.signOut();
    }
  } catch (_) {}

  runApp(const ProviderScope(child: SolenStayApp()));
}

class SolenStayApp extends ConsumerWidget {
  const SolenStayApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'SolenStay',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
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
