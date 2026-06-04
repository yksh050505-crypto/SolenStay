import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class PickedApk {
  final String name;
  final List<int> bytes;
  const PickedApk(this.name, this.bytes);
}

/// Web 브라우저에서 .apk 파일 하나를 선택하고 바이트로 읽어 반환.
/// 사용자가 취소하거나 파일이 없으면 null.
Future<PickedApk?> pickApkFile() async {
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.apk';
  // body에 잠시 붙여야 click()이 동작 (브라우저별)
  web.document.body?.appendChild(input);

  final completer = Completer<PickedApk?>();
  void cleanup() {
    try {
      web.document.body?.removeChild(input);
    } catch (_) {}
  }

  Future<void> handleChange() async {
    final files = input.files;
    if (files == null || files.length == 0) {
      cleanup();
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    final file = files.item(0);
    if (file == null) {
      cleanup();
      if (!completer.isCompleted) completer.complete(null);
      return;
    }
    try {
      final buffer = await file.arrayBuffer().toDart;
      final bytes = buffer.toDart.asUint8List();
      cleanup();
      if (!completer.isCompleted) completer.complete(PickedApk(file.name, bytes));
    } catch (e) {
      cleanup();
      if (!completer.isCompleted) completer.completeError(e);
    }
  }

  input.onchange = ((web.Event _) {
    // ignore: discarded_futures
    handleChange();
  }).toJS;

  // 취소(사용자가 다이얼로그 닫음)은 onchange가 안 불려서 timeout으로 처리하지 않음.
  // 대신 UI에서 다른 액션 들어오면 무시되도록 디자인됨.
  input.click();
  return completer.future;
}
