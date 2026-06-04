/// Web에서만 동작하는 APK 파일 선택기 — io 스텁.
/// Native (Android/iOS)에서는 UnimplementedError 반환.
class PickedApk {
  final String name;
  final List<int> bytes;
  const PickedApk(this.name, this.bytes);
}

Future<PickedApk?> pickApkFile() async {
  throw UnimplementedError(
    '파일 업로드는 웹 브라우저에서만 지원합니다. '
    'PC 브라우저에서 https://solenstay-74f8e.web.app 으로 접속해 등록하세요.',
  );
}
