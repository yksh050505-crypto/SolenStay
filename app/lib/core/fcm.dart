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

    // 알림 권한 요청은 디바이스/브라우저당 단 한 번만.
    // SharedPreferences에 "이미 요청 시도했음" 플래그를 영구 저장 → 사용자 결정(허용/거부) 후엔
    // 매 로그인마다 팝업이 다시 뜨지 않음. 권한 재요청은 사용자가 명시적으로(설정 등) 트리거할 때만.
    final prefs = await SharedPreferences.getInstance();
    const kAsked = 'fcm_permission_asked';
    NotificationSettings settings = await messaging.getNotificationSettings();
    final alreadyAsked = prefs.getBool(kAsked) ?? false;
    if (settings.authorizationStatus != AuthorizationStatus.authorized && !alreadyAsked) {
      // 첫 1회만 권한 요청 — 결과와 무관하게 플래그 저장
      settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      await prefs.setBool(kAsked, true);
    }
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint('[FCM] 알림 권한 없음 (status=${settings.authorizationStatus})');
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
