import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import 'models.dart';

// ===== 인스턴스 Provider =====
final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);
final authProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);
final functionsProvider = Provider<FirebaseFunctions>(
  (ref) => FirebaseFunctions.instanceFor(region: AppConstants.functionsRegion),
);

// ===== 인증 상태 =====
final firebaseUserProvider = StreamProvider<User?>(
  (ref) => ref.watch(authProvider).authStateChanges(),
);

/// 현재 로그인한 사용자의 Firestore 프로필 + Custom Claims role
final currentUserProvider = StreamProvider<UserModel?>((ref) {
  final user = ref.watch(firebaseUserProvider).value;
  if (user == null) return Stream.value(null);
  return ref
      .watch(firestoreProvider)
      .collection('users')
      .doc(user.uid)
      .snapshots()
      .map((snap) => snap.exists ? UserModel.fromDoc(snap) : null);
});

// ===== 호점 (인증된 사용자만) =====
final branchesProvider = StreamProvider<List<BranchModel>>((ref) {
  final user = ref.watch(firebaseUserProvider).value;
  if (user == null) return Stream.value(const <BranchModel>[]);

  return ref
      .watch(firestoreProvider)
      .collection('branches')
      .where('active', isEqualTo: true)
      .snapshots()
      .map((s) => s.docs.map(BranchModel.fromDoc).toList()
        ..sort((a, b) => a.id.compareTo(b.id)));
});

// ===== 청소 — 오늘자 (인증된 사용자만) =====
final todayCleaningsProvider = StreamProvider<List<CleaningModel>>((ref) {
  final user = ref.watch(firebaseUserProvider).value;
  if (user == null) return Stream.value(const <CleaningModel>[]);

  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 1));

  return ref
      .watch(firestoreProvider)
      .collection('cleanings')
      .where('scheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where('scheduledDate', isLessThan: Timestamp.fromDate(end))
      .snapshots()
      .map((s) => s.docs.map(CleaningModel.fromDoc).toList()
        ..sort((a, b) => a.branchId.compareTo(b.branchId)));
});

// ===== 청소 — 앞으로 (캘린더용) =====
// 윈도우를 upcomingReservationsProvider(오늘-7 ~ 오늘+60)와 동일하게 맞춰야
// 캘린더에 표시되는 모든 예약 pill이 청소 데이터를 갖게 되어 배정 여부 배지가 정확해짐.
final upcomingCleaningsProvider = StreamProvider<List<CleaningModel>>((ref) {
  final user = ref.watch(firebaseUserProvider).value;
  if (user == null) return Stream.value(const <CleaningModel>[]);

  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7));
  final end = start.add(const Duration(days: 67));

  return ref
      .watch(firestoreProvider)
      .collection('cleanings')
      .where('scheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where('scheduledDate', isLessThan: Timestamp.fromDate(end))
      .orderBy('scheduledDate')
      .snapshots()
      .map((s) => s.docs.map(CleaningModel.fromDoc).toList());
});

// ===== 다가오는 예약 (캘린더 바 + 체크인/체크아웃 표시용) =====
final upcomingReservationsProvider = StreamProvider<List<ReservationModel>>((ref) {
  final user = ref.watch(firebaseUserProvider).value;
  if (user == null) return Stream.value(const <ReservationModel>[]);

  final now = DateTime.now();
  // 오늘 - 7일 ~ 오늘 + 60일 (캘린더 현재월 + 다음월 표시에 충분)
  final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7));
  final end = start.add(const Duration(days: 67));

  return ref
      .watch(firestoreProvider)
      .collection('reservations')
      .where('checkOut', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where('checkOut', isLessThan: Timestamp.fromDate(end))
      .snapshots()
      .map((s) => s.docs.map(ReservationModel.fromDoc).toList()
        ..sort((a, b) => a.checkIn.compareTo(b.checkIn)));
});

// ===== 매니저용 — 미지정 청소 =====
/// 연간 미배정 청소 카운트 (오늘부터 1년 이내)
final unassignedYearCountProvider = StreamProvider<int>((ref) {
  final user = ref.watch(firebaseUserProvider).value;
  if (user == null) return Stream.value(0);

  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 365));

  return ref
      .watch(firestoreProvider)
      .collection('cleanings')
      .where('status', isEqualTo: 'unassigned')
      .where('scheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where('scheduledDate', isLessThan: Timestamp.fromDate(end))
      .snapshots()
      .map((s) => s.size);
});

final unassignedCleaningsProvider = StreamProvider<List<CleaningModel>>((ref) {
  final user = ref.watch(firebaseUserProvider).value;
  if (user == null) return Stream.value(const <CleaningModel>[]);

  final now = DateTime.now();
  return ref
      .watch(firestoreProvider)
      .collection('cleanings')
      .where('status', isEqualTo: 'unassigned')
      .where('scheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
      .orderBy('scheduledDate')
      .limit(20)
      .snapshots()
      .map((s) => s.docs.map(CleaningModel.fromDoc).toList());
});

// ===== Cloud Functions Wrapper =====
class FunctionsService {
  final FirebaseFunctions _fn;
  FunctionsService(this._fn);

  Future<List<String>> listLoginCandidates({bool adminOnly = false}) async {
    final res = await _fn.httpsCallable('listLoginCandidates').call({'adminOnly': adminOnly});
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['names'] as List<dynamic>).cast<String>();
  }

  Future<Map<String, dynamic>> signInWithPin({
    required String name,
    required String pin,
  }) async {
    final res = await _fn.httpsCallable('signInWithPin').call({'name': name, 'pin': pin});
    return Map<String, dynamic>.from(res.data as Map);
  }

  Future<void> changePin(String newPin) async {
    await _fn.httpsCallable('changePin').call({'newPin': newPin});
  }

  Future<void> updateUserPin({required String uid, required String pin}) async {
    await _fn.httpsCallable('updateUserPin').call({'uid': uid, 'pin': pin});
  }

  Future<void> deleteUser(String uid) async {
    await _fn.httpsCallable('deleteUser').call({'uid': uid});
  }

  /// iCal 즉시 동기화 (branchId 없으면 전체 호점)
  Future<Map<String, dynamic>> syncICalManual({String? branchId}) async {
    final res = await _fn.httpsCallable('syncICalManual').call({
      if (branchId != null) 'branchId': branchId,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// 본인 프로필 수정 (이름 / 프로필 사진 / 언어).
  /// photoUrl에 명시적으로 null을 넘기려면 clearPhoto=true 사용.
  Future<void> updateMyProfile({
    String? name,
    String? photoUrl,
    bool clearPhoto = false,
    String? language,
  }) async {
    await _fn.httpsCallable('updateMyProfile').call({
      if (name != null) 'name': name,
      if (clearPhoto) 'photoUrl': null else if (photoUrl != null) 'photoUrl': photoUrl,
      if (language != null) 'language': language,
    });
  }

  Future<void> claimCleaning(String cleaningId) async {
    await _fn.httpsCallable('claimCleaning').call({'cleaningId': cleaningId});
  }

  Future<void> releaseCleaning(String cleaningId) async {
    await _fn.httpsCallable('releaseCleaning').call({'cleaningId': cleaningId});
  }

  Future<void> forceAssignCleaning(String cleaningId, String uid) async {
    await _fn.httpsCallable('forceAssignCleaning').call({
      'cleaningId': cleaningId,
      'uid': uid,
    });
  }

  Future<void> completeCleaning({
    required String cleaningId,
    required List<ChecklistItem> checklist,
    required List<String> photoUrls,
    String memo = '',
  }) async {
    await _fn.httpsCallable('completeCleaning').call({
      'cleaningId': cleaningId,
      'checklist': checklist.map((c) => c.toMap()).toList(),
      'photoUrls': photoUrls,
      'memo': memo,
    });
  }

  Future<void> registerFcmToken(String token) async {
    await _fn.httpsCallable('registerFcmToken').call({'token': token});
  }

  Future<void> registerUser({
    required String name,
    required String pin,
    required String role,
  }) async {
    await _fn.httpsCallable('registerUser').call({'name': name, 'pin': pin, 'role': role});
  }

  /// 매니저 공지사항 작성
  /// @param target 'all' | 'cleaners' | 'admins'
  Future<Map<String, dynamic>> createManagerNotice({
    required String title,
    required String body,
    String target = 'all',
  }) async {
    final res = await _fn.httpsCallable('createManagerNotice').call({
      'title': title,
      'body': body,
      'target': target,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// 매니저 공지사항 수정 (작성자 본인만)
  Future<void> updateManagerNotice({
    required String notificationId,
    String? title,
    String? body,
  }) async {
    await _fn.httpsCallable('updateManagerNotice').call({
      'notificationId': notificationId,
      if (title != null) 'title': title,
      if (body != null) 'body': body,
    });
  }

  /// 매니저 공지사항 삭제 (작성자 본인만)
  Future<void> deleteManagerNotice(String notificationId) async {
    await _fn.httpsCallable('deleteManagerNotice').call({
      'notificationId': notificationId,
    });
  }
}

final functionsServiceProvider = Provider<FunctionsService>(
  (ref) => FunctionsService(ref.watch(functionsProvider)),
);

// ===== 프로필 사진 업로드 =====
final storageProvider = Provider<FirebaseStorage>((ref) => FirebaseStorage.instance);

/// 프로필 사진을 users/{uid}/profile.{ext} 에 업로드하고 다운로드 URL 반환.
Future<String> uploadProfilePhoto({
  required String uid,
  required Uint8List bytes,
  String ext = 'jpg',
}) async {
  final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';
  final ref = FirebaseStorage.instance.ref('users/$uid/profile.$ext');
  await ref.putData(bytes, SettableMetadata(contentType: contentType));
  return ref.getDownloadURL();
}

// ===== 앱 언어(Locale) =====
/// 사용자가 방금 선택한 언어를 즉시 반영하기 위한 오버라이드 (서버 동기화 전까지).
final localeOverrideProvider = StateProvider<Locale?>((ref) => null);

/// 실제 적용 Locale = 오버라이드 우선, 없으면 사용자 프로필의 language, 기본 ko.
final localeProvider = Provider<Locale>((ref) {
  final override = ref.watch(localeOverrideProvider);
  if (override != null) return override;
  final lang = ref.watch(currentUserProvider).valueOrNull?.language ?? 'ko';
  return Locale(lang);
});
