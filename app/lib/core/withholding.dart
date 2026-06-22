/// 프리랜서 사업소득 원천징수(3.3%) 계산.
///
/// 정책: **2026년 7월 지급분부터** 청소원·실장에게 3.3%를 공제한다.
/// 그 이전(2026년 6월 이하)은 회사부담(그로스업)이므로 화면에는 총지급액을 그대로 보여준다.
///
/// 계산은 **사람별·월 지급액(gross) 기준**으로 한다(홈택스/위택스 신고 방식과 동일):
///   - 소득세      = 지급액 × 3%   (원미만 절사)
///   - 지방소득세  = 소득세 × 10%  (10원미만 절사)
///   - 원천세 합계 = 소득세 + 지방소득세,   실지급액 = 지급액 − 원천세
///
/// 검산: 1,000,000원 → 소득세 30,000 + 지방세 3,000 = 33,000, 실지급 967,000 (정확히 3.3%).
library;

/// 원천징수 적용 시작 월. 선택한 월이 이 달 이상이면 공제를 표시한다.
final DateTime kWithholdingFromMonth = DateTime(2026, 7);

/// 해당 월(연·월)에 원천징수가 적용되는지.
bool withholdingAppliesTo(DateTime month) =>
    !DateTime(month.year, month.month).isBefore(kWithholdingFromMonth);

/// 한 사람의 월 지급액에 대한 원천징수 내역.
class Withholding {
  /// 총지급액(원).
  final int gross;

  /// 소득세(원) = 지급액 × 3%, 원미만 절사.
  final int incomeTax;

  /// 지방소득세(원) = 소득세 × 10%, 10원미만 절사.
  final int localTax;

  const Withholding._(this.gross, this.incomeTax, this.localTax);

  /// 원천세 합계(소득세 + 지방소득세).
  int get tax => incomeTax + localTax;

  /// 실지급액(총지급액 − 원천세).
  int get net => gross - tax;

  /// 지급액으로부터 원천세 내역을 계산.
  factory Withholding.of(int gross) {
    if (gross <= 0) return const Withholding._(0, 0, 0);
    final income = gross * 3 ~/ 100; // 원미만 절사
    final local = (income ~/ 100) * 10; // 소득세×10%, 10원미만 절사
    return Withholding._(gross, income, local);
  }
}
