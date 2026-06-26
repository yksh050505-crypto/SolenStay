import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// 브라우저에서 바이트를 파일로 다운로드한다 (Blob + 임시 <a> 클릭).
/// apk_picker_web.dart 와 동일한 package:web 기반 패턴.
void downloadBytes(
  String filename,
  List<int> bytes, {
  String mimeType = 'application/octet-stream',
}) {
  final data = Uint8List.fromList(bytes);
  final blob = web.Blob(
    <JSAny>[data.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
