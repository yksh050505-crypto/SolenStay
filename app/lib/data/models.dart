import 'package:cloud_firestore/cloud_firestore.dart';

/// 사용자 (매니저/실장/청소원)
class UserModel {
  final String uid;
  final String name;
  final String role; // 'manager' | 'chief' | 'cleaner'
  final bool pinChanged;
  final bool active;
  final List<String> fcmTokens;

  UserModel({
    required this.uid,
    required this.name,
    required this.role,
    required this.pinChanged,
    required this.active,
    required this.fcmTokens,
  });

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
  final String status; // 'unassigned' | 'assigned' | 'in_progress' | 'completed'
  final List<ChecklistItem> checklist;
  final List<String> photoUrls;
  final String memo;
  final DateTime? completedAt;

  CleaningModel({
    required this.id,
    required this.branchId,
    required this.reservationId,
    required this.scheduledDate,
    this.assigneeUid,
    required this.status,
    required this.checklist,
    required this.photoUrls,
    required this.memo,
    this.completedAt,
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
      status: d['status'] as String? ?? 'unassigned',
      checklist: items,
      photoUrls: (d['photoUrls'] as List<dynamic>?)?.cast<String>() ?? const [],
      memo: d['memo'] as String? ?? '',
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
    );
  }
}
