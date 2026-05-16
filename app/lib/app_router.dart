import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/services.dart';
import 'features/auth/pin_login_page.dart';
import 'features/home/home_page.dart';
import 'features/cleaning_detail/cleaning_detail_page.dart';
import 'features/completion/completion_page.dart';
import 'features/calendar/calendar_page.dart';
import 'features/profile/profile_page.dart';
import 'features/manager/manager_dashboard_page.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: _AuthRefresher(ref),
    redirect: (context, state) {
      final user = ref.read(firebaseUserProvider).value;
      final isLogin = state.matchedLocation == '/';
      if (user == null && !isLogin) return '/';
      if (user != null && isLogin) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const PinLoginPage()),
      GoRoute(path: '/home', builder: (_, __) => const HomePage()),
      GoRoute(
        path: '/cleaning/:id',
        builder: (_, s) => CleaningDetailPage(cleaningId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/cleaning/:id/complete',
        builder: (_, s) => CompletionPage(cleaningId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/calendar', builder: (_, __) => const CalendarPage()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
      GoRoute(path: '/manager', builder: (_, __) => const ManagerDashboardPage()),
    ],
  );
});

class _AuthRefresher extends ChangeNotifier {
  _AuthRefresher(Ref ref) {
    ref.listen(firebaseUserProvider, (_, __) => notifyListeners());
  }
}
