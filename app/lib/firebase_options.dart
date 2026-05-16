// 자동 생성 예정 (flutterfire configure로 덮어씀)
// 임시 수동 작성: Web 전용 (Flutter Web 빌드 우선)
//
// 실제 배포 전 다음 명령 실행 권장:
//   dart pub global activate flutterfire_cli
//   flutterfire configure --project=solenstay-74f8e
//
// 그러면 이 파일이 자동으로 재생성되고 Android/iOS도 추가됨.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'SolenStay v0.1은 Web 전용입니다. 다른 플랫폼은 flutterfire configure 후 지원.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCHiZRx45N4OhRGLK27fdnqPtfmug8g500',
    authDomain: 'solenstay-74f8e.firebaseapp.com',
    projectId: 'solenstay-74f8e',
    storageBucket: 'solenstay-74f8e.firebasestorage.app',
    messagingSenderId: '263114028567',
    appId: '1:263114028567:web:63dba99381195fa387ce52',
  );
}
