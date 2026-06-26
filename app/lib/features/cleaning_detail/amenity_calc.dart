/// 어메니티 세팅 수량 자동 계산 (순수 Dart, UI 없음)
///
/// 다음 손님의 인원수(P)와 숙박일수(N)를 기준으로 객실에 세팅할
/// 어메니티 품목별 수량을 계산한다. 화면에 보기 좋게 뿌리도록
/// 그룹(섹션)별 [AmenityItem] 리스트를 반환한다.
library;

/// 단일 어메니티 품목 (화면 표시용)
class AmenityItem {
  /// 품목명 (예: '샴푸')
  final String name;

  /// 수량 표시 문자열 (예: '8개 (2명×4박)', '통으로 제공')
  final String qty;

  const AmenityItem({required this.name, required this.qty});
}

/// 어메니티 그룹 (섹션 헤더 + 품목들)
class AmenityGroup {
  final String title;
  final List<AmenityItem> items;

  const AmenityGroup({required this.title, required this.items});
}

/// 인원 구간별 수량 (면도기/레이디세트 규칙):
/// 1명=1 / 2~4명=2 / 5~8명=3 / 9~10명=4 / 그 이상=4
int _occupancyTier(int guests) {
  if (guests <= 1) return 1;
  if (guests <= 4) return 2;
  if (guests <= 8) return 3;
  return 4; // 9명 이상
}

/// 다음 손님 기준 어메니티 세팅 수량 계산.
///
/// [guests] 인원수 P (최소 1로 보정), [nights] 숙박일수 N (최소 1로 보정).
List<AmenityGroup> calcAmenityGroups({required int guests, required int nights}) {
  final p = guests < 1 ? 1 : guests;
  final n = nights < 1 ? 1 : nights;
  final pn = p * n;
  final pnLabel = '($p명×$n박)';

  // ① P×N 개 — 단 샴푸·컨디셔너·바디워시는 N>=3이면 "통으로 제공"
  String perNightBottle() => n >= 3 ? '통으로 제공' : '$pn개 $pnLabel';
  final consumables = AmenityGroup(
    title: '소모품 (인원×숙박일)',
    items: [
      AmenityItem(name: '샴푸', qty: perNightBottle()),
      AmenityItem(name: '컨디셔너', qty: perNightBottle()),
      AmenityItem(name: '바디워시', qty: perNightBottle()),
      AmenityItem(name: '스킨토너', qty: '$pn개 $pnLabel'),
      AmenityItem(name: '에멀전', qty: '$pn개 $pnLabel'),
      AmenityItem(name: '폼클렌징', qty: '$pn개 $pnLabel'),
    ],
  );

  // ② 인원 기준
  // 칫솔&치약: N<=3 -> P개 / N>=4 -> 2P개
  final brushQty = n >= 4 ? '${p * 2}개 ($p명×2)' : '$p개 ($p명)';
  final perGuest = AmenityGroup(
    title: '인원 기준',
    items: [
      AmenityItem(name: '칫솔 & 치약', qty: brushQty),
      AmenityItem(name: '실내화', qty: '$p개 ($p명)'),
    ],
  );

  // ③ 인원 구간별
  final tier = _occupancyTier(p);
  final tierGroup = AmenityGroup(
    title: '인원 구간 기준',
    items: [
      AmenityItem(name: '면도기', qty: '$tier개'),
      AmenityItem(name: '레이디세트', qty: '$tier개'),
    ],
  );

  // ④ 엑스트라베드: P>=7명이면 1개 추가
  final extraGroup = AmenityGroup(
    title: '추가 비품',
    items: [
      AmenityItem(name: '엑스트라베드', qty: p >= 7 ? '1개' : '0개'),
    ],
  );

  return [consumables, perGuest, tierGroup, extraGroup];
}
