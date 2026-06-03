import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/services.dart';
import 'app_navigator.dart';
import 'fcm_notification_io.dart' if (dart.library.js_interop) 'fcm_notification_web.dart';

/// Web Push VAPID 공개 키
const String kVapidKey = 'BBy5ivktB2sNkH6kCrLPs-qTbsPMGCxwUkXPmjpxBnv8cbH7UrRikARBlKxA0VOLw75A5-TOWfjZvpyyyFAol6w';

/// FCM 메시지 데이터로 라우팅
void _handleNotificationClick(Map<String, dynamic> data) {
  final type = data['type'] as String?;
  final id = data['cleaningId'] as String? ?? data['id'] as String?;
  final router = AppNavigator.router;
  if (router == null) return;
  switch (type) {
    case 'cleaning':
    case 'unassigned':
      if (id != null) router.push('/cleaning/$id');
      break;
    case 'notice':
    default:
      router.push('/notifications');
  }
}

/// 로그인 후 호출 — 알림 권한 요청 + FCM 토큰을 서버에 등록
Future<void> initFcmForUser(FunctionsService fn) async {
  try {
    final messaging = FirebaseMessaging.instance;

    // 자동 권한 요청 안 함 — 일부 브라우저(삼성 인터넷 등)가 권한 저장을 매번 reset해서
    // 자동 요청 시 팝업이 매 로그인마다 뜨는 문제. 사용자가 내정보 화면에서 명시적 액션으로 요청해야 함.
    final settings = await messaging.getNotificationSettings();
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint('[FCM] 알림 권한 없음 (status=${settings.authorizationStatus}) — 내정보에서 켤 수 있음');
      return;
    }

    String? token;
    if (kIsWeb) {
      token = await messaging.getToken(vapidKey: kVapidKey);
    } else {
      token = await messaging.getToken();
    }

    if (token == null || token.isEmpty) {
      debugPrint('[FCM] 토큰 획득 실패');
      return;
    }

    debugPrint('[FCM] 토큰: ${token.substring(0, 20)}...');
    await fn.registerFcmToken(token);

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      fn.registerFcmToken(newToken);
    });

    // 포그라운드 메시지 — 브라우저 알림 표시
    FirebaseMessaging.onMessage.listen((message) {
      final title = message.notification?.title ?? 'SolenStay';
      final body = message.notification?.body ?? '';
      debugPrint('[FCM] 포그라운드: $title / $body');
      showForegroundNotification(title, body);
    });

    // 알림 클릭 → 앱이 백그라운드에서 깨어나는 경우
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationClick(message.data);
    });
    // 알림 클릭으로 앱이 시작된 경우
    final initial = await messaging.getInitialMessage();
    if (initial != null) {
      _handleNotificationClick(initial.data);
    }
  } catch (e) {
    debugPrint('[FCM] 초기화 오류: $e');
  }
}

/// 사용자가 명시적으로 알림 권한을 요청할 때 호출 (내정보 화면의 버튼 등).
/// 반환값: 권한 부여 성공 여부.
Future<bool> requestNotificationPermissionExplicit(FunctionsService fn) async {
  try {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      return false;
    }
    String? token;
    if (kIsWeb) {
      token = await messaging.getToken(vapidKey: kVapidKey);
    } else {
      token = await messaging.getToken();
    }
    if (token == null || token.isEmpty) return false;
    await fn.registerFcmToken(token);
    return true;
  } catch (e) {
    debugPrint('[FCM] 명시적 권한 요청 오류: $e');
    return false;
  }
}

/// 현재 알림 권한 상태 (UI 표시용)
Future<AuthorizationStatus> currentNotificationStatus() async {
  final s = await FirebaseMessaging.instance.getNotificationSettings();
  return s.authorizationStatus;
}
