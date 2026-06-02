import 'package:flutter/widgets.dart';

/// 경량 다국어 헬퍼 — 인라인 ko/en 페어 방식.
///
/// 사용: `L10n.of(context).t('내정보', 'My Info')`
/// 화면 텍스트를 점진적으로 이 헬퍼로 감싸 영어 전환을 확대할 수 있다.
/// Flutter 기본 위젯(날짜 선택기 등)은 MaterialApp.locale로 즉시 로케일을 따른다.
class L10n {
  final String lang; // 'ko' | 'en'
  const L10n(this.lang);

  static L10n of(BuildContext context) =>
      L10n(Localizations.localeOf(context).languageCode == 'en' ? 'en' : 'ko');

  bool get isEn => lang == 'en';

  /// 한국어/영어 문자열 중 현재 언어에 맞는 것을 반환.
  String t(String ko, String en) => isEn ? en : ko;
}
