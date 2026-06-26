/// 네이티브(안드로이드) 스텁.
/// 숙박일지(.hwpx) 내보내기는 매니저 PC(웹 크롬)에서만 동작한다.
/// 폰 앱에서 호출되면 명확한 안내 메시지로 막는다.
void downloadBytes(
  String filename,
  List<int> bytes, {
  String mimeType = 'application/octet-stream',
}) {
  throw UnsupportedError('파일 내보내기는 매니저 PC(크롬)에서만 지원됩니다.');
}
