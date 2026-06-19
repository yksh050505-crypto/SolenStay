import 'package:cloud_firestore/cloud_firestore.dart';

/// 사용자 (매니저/실장/청소원)
class UserModel {
  final String uid;
  final String name;
  final String role; // 'manager' | 'chief' | 'cleaner'
  final bool pinChanged;
  final bool active;
  final List<String> fcmTokens;
  final String? photoUrl;
  final String language; // 'ko' | 'en'
  /// 알림 수신 설정 — 키: 'newCleaning' | 'managerNotice' | 'scheduleChange'
  /// 값이 false면 해당 종류 알림 차단. 기본값(없으면) true로 간주.
  final Map<String, bool> notificationPrefs;

  UserModel({
    required this.uid,
    required this.name,
    required this.role,
    required this.pinChanged,
    required this.active,
    required this.fcmTokens,
    this.photoUrl,
    this.language = 'ko',
    this.notificationPrefs = const {},
  });

  bool prefEnabled(String key) => notificationPrefs[key] ?? true;

  bool get isManager => role == 'manager';
  bool get isChief => role == 'chief';
  bool get isCleaner => role == 'cleaner';
  bool get canManageDashboard => isManager || isChief;

  factory UserModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return UserModel(
      uid: doc.id,
      name: d['name'] as String? ?? '',
      role: d['role'] as String? ?? 'cleaner',
      pinChanged: d['pinChanged'] as bool? ?? false,
      active: d['active'] as bool? ?? true,
      fcmTokens: (d['fcmTokens'] as List<dynamic>?)?.cast<String>() ?? const [],
      photoUrl: d['photoUrl'] as String?,
      language: d['language'] as String? ?? 'ko',
      notificationPrefs: (d['notificationPrefs'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as bool? ?? true)) ??
          const {},
    );
  }
}

/// 호점
class BranchModel {
  final String id;
  final String name;
  final int rooms;
  final int maxOccupancy;
  final String color;
  final String iCalSourceUrl;
  final bool active;

  BranchModel({
    required this.id,
    required this.name,
    required this.rooms,
    required this.maxOccupancy,
    required this.color,
    required this.iCalSourceUrl,
    required this.active,
  });

  factory BranchModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return BranchModel(
      id: doc.id,
      name: d['name'] as String? ?? '',
      rooms: (d['rooms'] as num?)?.toInt() ?? 0,
      maxOccupancy: (d['maxOccupancy'] as num?)?.toInt() ?? 0,
      color: d['color'] as String? ?? '#64748B',
      iCalSourceUrl: d['iCalSourceUrl'] as String? ?? '',
      active: d['active'] as bool? ?? true,
    );
  }
}

/// 예약 (OTA에서 동기화)
class ReservationModel {
  final String id;
  final String branchId;
  final String ota;
  final String guestName;
  final int guestCount;
  final DateTime checkIn;
  final DateTime checkOut;

  ReservationModel({
    required this.id,
    required this.branchId,
    required this.ota,
    required this.guestName,
    required this.guestCount,
    required this.checkIn,
    required this.checkOut,
  });

  factory ReservationModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ReservationModel(
      id: doc.id,
      branchId: d['branchId'] as String? ?? '',
      ota: d['ota'] as String? ?? 'unknown',
      guestName: d['guestName'] as String? ?? '',
      guestCount: (d['guestCount'] as num?)?.toInt() ?? 0,
      checkIn: (d['checkIn'] as Timestamp).toDate(),
      checkOut: (d['checkOut'] as Timestamp).toDate(),
    );
  }
}

/// 체크리스트 항목
class ChecklistItem {
  final String category;
  final String text;
  final bool checked;

  ChecklistItem({required this.category, required this.text, this.checked = false});

  factory ChecklistItem.fromMap(Map<String, dynamic> m) => ChecklistItem(
        category: m['category'] as String? ?? '',
        text: m['text'] as String? ?? '',
        checked: m['checked'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'category': category,
        'text': text,
        'checked': checked,
      };

  ChecklistItem copyWith({bool? checked}) => ChecklistItem(
        category: category,
        text: text,
        checked: checked ?? this.checked,
      );
}

/// 청소 작업
class CleaningModel {
  final String id;
  final String branchId;
  final String reservationId;
  final DateTime scheduledDate;
  final String? assigneeUid;
  final String? assigneeName; // 담당자 이름 (denormalize, 실장도 읽기 위함)
  final String status; // 'unassigned' | 'assigned' | 'in_progress' | 'completed'
  final List<ChecklistItem> checklist;
  final List<String> photoUrls;
  final String memo;
  final DateTime? completedAt;
  final Map<String, dynamic>? nextGuestSnapshot;

  CleaningModel({
    required this.id,
    required this.branchId,
    required this.reservationId,
    required this.scheduledDate,
    this.assigneeUid,
    this.assigneeName,
    required this.status,
    required this.checklist,
    required this.photoUrls,
    required this.memo,
    this.completedAt,
    this.nextGuestSnapshot,
  });

  bool get isUnassigned => status == 'unassigned';
  bool get isAssigned => status == 'assigned';
  bool get isCompleted => status == 'completed';
  int get checkedCount => checklist.where((i) => i.checked).length;
  bool get allChecked => checklist.isNotEmpty && checklist.every((i) => i.checked);

  factory CleaningModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    final items = (d['checklist'] as List<dynamic>? ?? [])
        .map((e) => ChecklistItem.fromMap(e as Map<String, dynamic>))
        .toList();
    return CleaningModel(
      id: doc.id,
      branchId: d['branchId'] as String? ?? '',
      reservationId: d['reservationId'] as String? ?? '',
      scheduledDate: (d['scheduledDate'] as Timestamp).toDate(),
      assigneeUid: d['assigneeUid'] as String?,
      assigneeName: d['assigneeName'] as String?,
      status: d['status'] as String? ?? 'unassigned',
      checklist: items,
      photoUrls: (d['photoUrls'] as List<dynamic>?)?.cast<String>() ?? const [],
      memo: d['memo'] as String? ?? '',
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
      nextGuestSnapshot: (d['nextGuestSnapshot'] as Map<String, dynamic>?),
    );
  }
}

/// 급여 설정 (Firestore: config/salary)
/// 근무자(uid)별 '청소 1건당 단가'(원). 매니저가 관리자 설정에서 설정한다.
/// 월급 = 해당 월 완료 청소 건수 × ratePerCleaning[uid].
class SalaryConfigModel {
  /// uid → 청소 1건당 단가(원)
  final Map<String, int> ratePerCleaning;
  final DateTime? updatedAt;

  const SalaryConfigModel({
    this.ratePerCleaning = const {},
    this.updatedAt,
  });

  /// 해당 근무자의 건당 단가 (미설정이면 0).
  int rateOf(String uid) => ratePerCleaning[uid] ?? 0;

  factory SalaryConfigModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final raw = (d['ratePerCleaning'] as Map<String, dynamic>?) ?? const {};
    return SalaryConfigModel(
      ratePerCleaning: raw.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// 앱 버전 (Firestore: config/appVersion)
/// 매니저가 새 APK 업로드 후 등록 → 모든 클라이언트가 시작 시 비교 → 다이얼로그
class AppVersionModel {
  final String latest;       // 예: "0.2.0" — 표시·기록용
  final int latestCode;      // 정수 비교 기준 (pubspec.yaml의 buildNumber와 동일)
  final String apkUrl;       // 다운로드 링크 (구글 드라이브 / Firebase Storage / GitHub Releases)
  final String releaseNotes; // 변경 내용 (Korean)
  final bool mandatory;      // true면 다이얼로그 닫기 불가
  final DateTime? updatedAt;

  const AppVersionModel({
    required this.latest,
    required this.latestCode,
    required this.apkUrl,
    this.releaseNotes = '',
    this.mandatory = false,
    this.updatedAt,
  });

  factory AppVersionModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return AppVersionModel(
      latest: d['latest'] as String? ?? '',
      latestCode: (d['latestCode'] as num?)?.toInt() ?? 0,
      apkUrl: d['apkUrl'] as String? ?? '',
      releaseNotes: d['releaseNotes'] as String? ?? '',
      mandatory: d['mandatory'] as bool? ?? false,
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'latest': latest,
        'latestCode': latestCode,
        'apkUrl': apkUrl,
        'releaseNotes': releaseNotes,
        'mandatory': mandatory,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
