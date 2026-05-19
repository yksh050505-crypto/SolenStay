import 'dart:js_interop';

@JS('Notification')
extension type _Notification._(JSObject _) implements JSObject {
  external _Notification(String title, JSAny? options);
}

@JS('Notification.permission')
external String get _permission;

/// 포그라운드 메시지 수신 시 브라우저 시스템 알림 표시
void showForegroundNotification(String title, String body) {
  if (_permission != 'granted') return;
  final opts = {'body': body, 'icon': '/icons/Icon-192.png'}.jsify();
  _Notification(title, opts);
}
