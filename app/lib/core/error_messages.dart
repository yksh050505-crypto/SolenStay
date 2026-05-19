/// Firebase/Cloud Functions 에러를 사용자 친화 메시지로 변환
String friendlyError(Object e) {
  final s = e.toString();
  if (s.contains('permission-denied')) return '권한이 없습니다';
  if (s.contains('unauthenticated')) return '로그인이 필요합니다';
  if (s.contains('not-found')) return '데이터를 찾을 수 없습니다';
  if (s.contains('already-exists')) return '이미 처리된 작업입니다';
  if (s.contains('failed-precondition')) return '지금은 처리할 수 없습니다';
  if (s.contains('invalid-argument')) return '입력값이 올바르지 않습니다';
  if (s.contains('deadline-exceeded') || s.contains('timeout')) return '응답 시간이 초과되었습니다. 다시 시도해주세요';
  if (s.contains('unavailable') || s.contains('network')) return '네트워크 연결을 확인해주세요';
  if (s.contains('invalid name or pin')) return '이름 또는 PIN이 올바르지 않습니다';
  if (s.contains('PIN은') || s.contains('단순한 PIN')) {
    // 서버 메시지가 한글이면 그대로 사용
    final match = RegExp(r'message: ([^,)]+)').firstMatch(s);
    if (match != null) return match.group(1)!.trim();
  }
  return '문제가 발생했습니다. 다시 시도해주세요';
}
