import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

// ===== 호점 =====
final branchesProvider = StreamProvider<List<BranchModel>>((ref) {
  return ref
      .watch(firestoreProvider)
      .collection('branches')
      .where('active', isEqualTo: true)
      .snapshots()
      .map((s) => s.docs.map(BranchModel.fromDoc).toList()
        ..sort((a, b) => a.id.compareTo(b.id)));
});

// ===== 청소 — 오늘자 =====
final todayCleaningsProvider = StreamProvider<List<CleaningModel>>((ref) {
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
final upcomingCleaningsProvider = StreamProvider<List<CleaningModel>>((ref) {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 31));

  return ref
      .watch(firestoreProvider)
      .collection('cleanings')
      .where('scheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
      .where('scheduledDate', isLessThan: Timestamp.fromDate(end))
      .orderBy('scheduledDate')
      .snapshots()
      .map((s) => s.docs.map(CleaningModel.fromDoc).toList());
});

// ===== 매니저용 — 미지정 청소 =====
final unassignedCleaningsProvider = StreamProvider<List<CleaningModel>>((ref) {
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

  Future<List<String>> listLoginCandidates() async {
    final res = await _fn.httpsCallable('listLoginCandidates').call();
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
}

final functionsServiceProvider = Provider<FunctionsService>(
  (ref) => FunctionsService(ref.watch(functionsProvider)),
);
