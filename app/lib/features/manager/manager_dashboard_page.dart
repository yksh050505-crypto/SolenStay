import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';

/// 전체 사용자 목록 Provider (매니저용)
final allUsersProvider = StreamProvider<List<UserModel>>((ref) {
  final authUser = ref.watch(firebaseUserProvider).value;
  if (authUser == null) return Stream.value(const <UserModel>[]);

  return ref
      .watch(firestoreProvider)
      .collection('users')
      .where('active', isEqualTo: true)
      .snapshots()
      .map((s) => s.docs.map(UserModel.fromDoc).toList()..sort((a, b) => a.name.compareTo(b.name)));
});

/// 최근 메모(특이사항) Provider — 완료된 청소 중 memo가 있는 것
final recentNotesProvider = StreamProvider<List<CleaningModel>>((ref) {
  final authUser = ref.watch(firebaseUserProvider).value;
  if (authUser == null) return Stream.value(const <CleaningModel>[]);

  return ref
      .watch(firestoreProvider)
      .collection('cleanings')
      .where('status', isEqualTo: 'completed')
      .orderBy('completedAt', descending: true)
      .limit(10)
      .snapshots()
      .map((s) => s.docs
          .map(CleaningModel.fromDoc)
          .where((c) => c.memo.isNotEmpty)
          .take(5)
          .toList());
});

/// ⑦ 매니저 대시보드 (manager/chief 전용) - 목업 디자인 적용
class ManagerDashboardPage extends ConsumerWidget {
  const ManagerDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    if (userAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('매니저 대시보드'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final user = userAsync.value;
    if (user == null || !user.canManageDashboard) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('권한 없음'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 48, color: AppColors.dim),
              SizedBox(height: 12),
              Text('매니저/실장만 접근 가능합니다', style: TextStyle(color: AppColors.muted)),
            ],
          ),
        ),
      );
    }

    final todayCleanings = ref.watch(todayCleaningsProvider);
    final unassigned = ref.watch(unassignedCleaningsProvider);
    final branches = ref.watch(branchesProvider).value ?? const <BranchModel>[];
    final notes = ref.watch(recentNotesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('매니저 대시보드'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            // 인사 영역
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('관리자', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('M월 d일 (E)', 'ko').format(DateTime.now()),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 2x2 통계 카드 (오늘 체크아웃 / 오늘 체크인 / 청소 완료 / 미지정 청소)
            todayCleanings.when(
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
              error: (e, _) => Text('오류: $e'),
              data: (todayList) {
                return unassigned.when(
                  loading: () => _StatsGrid(
                    checkOuts: todayList.length,
                    checkIns: 0,
                    completed: todayList.where((c) => c.isCompleted).length,
                    unassigned: 0,
                  ),
                  error: (_, __) => _StatsGrid(
                    checkOuts: todayList.length,
                    checkIns: 0,
                    completed: todayList.where((c) => c.isCompleted).length,
                    unassigned: 0,
                  ),
                  data: (unList) => _StatsGrid(
                    checkOuts: todayList.length,
                    checkIns: todayList.length, // TODO: reservations에서 체크인 카운트
                    completed: todayList.where((c) => c.isCompleted).length,
                    unassigned: unList.length,
                  ),
                );
              },
            ),
            const SizedBox(height: 22),

            // 특이사항 섹션
            _SectionHeader(title: '특이사항', actionText: ''),
            const SizedBox(height: 10),
            notes.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('오류: $e', style: const TextStyle(color: AppColors.danger)),
              data: (list) {
                if (list.isEmpty) {
                  return _emptyBox('아직 등록된 특이사항이 없습니다');
                }
                return Column(
                  children: list.map((c) => _NoteCard(cleaning: c, branches: branches)).toList(),
                );
              },
            ),
            const SizedBox(height: 22),

            // 미지정 청소 섹션
            _SectionHeader(
              title: '청소 일정 미입력',
              danger: true,
              count: unassigned.value?.length ?? 0,
            ),
            const SizedBox(height: 4),
            const Text(
              'iCal 예약 ↔ 청소원 배정 비교',
              style: TextStyle(color: AppColors.dim, fontSize: 11),
            ),
            const SizedBox(height: 8),
            unassigned.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('오류: $e', style: const TextStyle(color: AppColors.danger)),
              data: (list) {
                if (list.isEmpty) {
                  return _emptyBox('모든 청소가 배정 완료!', icon: Icons.check_circle_outline, color: AppColors.ok);
                }
                return Column(
                  children: list.map((c) => _UnassignedCard(
                    cleaning: c,
                    branches: branches,
                    onAssign: () => _showAssignDialog(context, ref, c),
                  )).toList(),
                );
              },
            ),
            const SizedBox(height: 24),

            // 청소원 현황 (목업에는 없지만 유용한 추가 기능)
            _SectionHeader(title: '청소원'),
            const SizedBox(height: 10),
            Consumer(builder: (context, ref, _) {
              final users = ref.watch(allUsersProvider);
              return users.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('오류: $e'),
                data: (list) {
                  final cleaners = list.where((u) => u.isCleaner).toList();
                  if (cleaners.isEmpty) {
                    return _emptyBox('등록된 청소원이 없습니다');
                  }
                  return Column(
                    children: cleaners.map((u) => _UserCard(user: u)).toList(),
                  );
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _emptyBox(String text, {IconData? icon, Color? color}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (color ?? AppColors.muted).withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color ?? AppColors.muted, size: 18),
            const SizedBox(width: 8),
          ],
          Text(
            text,
            style: TextStyle(color: color ?? AppColors.muted, fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Future<void> _showAssignDialog(BuildContext context, WidgetRef ref, CleaningModel cleaning) async {
    final users = ref.read(allUsersProvider).value ?? [];
    final cleaners = users.where((u) => u.isCleaner).toList();
    if (cleaners.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('배정할 청소원이 없습니다')),
      );
      return;
    }
    final selected = await showDialog<UserModel>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('청소원 배정'),
        children: cleaners.map((u) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, u),
          child: Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: const BoxDecoration(color: AppColors.branch1, shape: BoxShape.circle),
                child: Center(
                  child: Text(u.name[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
              const SizedBox(width: 12),
              Text(u.name, style: const TextStyle(fontSize: 14)),
            ],
          ),
        )).toList(),
      ),
    );

    if (selected == null) return;
    try {
      await ref.read(functionsServiceProvider).forceAssignCleaning(cleaning.id, selected.uid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${selected.name}님에게 배정했습니다'), backgroundColor: AppColors.ok),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('배정 실패: $e')));
      }
    }
  }
}

// ===== 2x2 통계 카드 =====

class _StatsGrid extends StatelessWidget {
  final int checkOuts;
  final int checkIns;
  final int completed;
  final int unassigned;
  const _StatsGrid({
    required this.checkOuts,
    required this.checkIns,
    required this.completed,
    required this.unassigned,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 8,
      mainAxisSpacing: 8,
      childAspectRatio: 1.7,
      children: [
        _statCard('$checkOuts', '오늘 체크아웃', sub: '1·2·3호점', color: AppColors.text),
        _statCard('$checkIns', '오늘 체크인', sub: '예약 기준', color: AppColors.text),
        _statCard('$completed', '청소 완료', sub: '진행 ${checkOuts - completed}건', color: AppColors.ok),
        _statCard(
          '$unassigned',
          '미지정 청소',
          sub: unassigned > 0 ? '⚠ 확인 필요' : '없음',
          color: unassigned > 0 ? AppColors.danger : AppColors.muted,
          subColor: unassigned > 0 ? AppColors.danger : AppColors.muted,
        ),
      ],
    );
  }

  Widget _statCard(String num, String label, {String? sub, required Color color, Color? subColor}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(num, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600)),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub, style: TextStyle(color: subColor ?? AppColors.muted, fontSize: 10)),
          ],
        ],
      ),
    );
  }
}

// ===== 섹션 헤더 =====

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionText;
  final bool danger;
  final int? count;
  const _SectionHeader({required this.title, this.actionText, this.danger = false, this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            if (danger) ...[
              const Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 16),
              const SizedBox(width: 4),
            ],
            Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text),
            ),
            if (count != null && count! > 0) ...[
              const SizedBox(width: 6),
              Text(
                '($count건)',
                style: TextStyle(
                  color: danger ? AppColors.danger : AppColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        if (actionText != null && actionText!.isNotEmpty)
          Text(actionText!, style: const TextStyle(color: AppColors.branch1, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ===== 특이사항 카드 =====

class _NoteCard extends ConsumerWidget {
  final CleaningModel cleaning;
  final List<BranchModel> branches;
  const _NoteCard({required this.cleaning, required this.branches});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = branches.firstWhere(
      (b) => b.id == cleaning.branchId,
      orElse: () => BranchModel(id: cleaning.branchId, name: cleaning.branchId, rooms: 0, maxOccupancy: 0, color: '#64748B', iCalSourceUrl: '', active: true),
    );
    final branchColor = AppColors.branchColor(cleaning.branchId);
    final assigneeName = _useAssigneeName(ref, cleaning.assigneeUid);
    final dateStr = DateFormat('M/d (E)', 'ko').format(cleaning.scheduledDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 52),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: branchColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: Text(
              branch.name,
              style: TextStyle(color: branchColor, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$assigneeName · $dateStr',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                    if (cleaning.photoUrls.isNotEmpty)
                      Text(
                        '📷 ${cleaning.photoUrls.length}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 11),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  cleaning.memo,
                  style: const TextStyle(fontSize: 12, color: AppColors.text, height: 1.4),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _useAssigneeName(WidgetRef ref, String? uid) {
    if (uid == null || uid.isEmpty) return '미지정';
    final users = ref.watch(allUsersProvider).value ?? [];
    final found = users.where((u) => u.uid == uid).toList();
    return found.isNotEmpty ? found.first.name : '청소원';
  }
}

// ===== 미지정 청소 카드 =====

class _UnassignedCard extends StatelessWidget {
  final CleaningModel cleaning;
  final List<BranchModel> branches;
  final VoidCallback onAssign;
  const _UnassignedCard({required this.cleaning, required this.branches, required this.onAssign});

  @override
  Widget build(BuildContext context) {
    final branch = branches.firstWhere(
      (b) => b.id == cleaning.branchId,
      orElse: () => BranchModel(id: cleaning.branchId, name: cleaning.branchId, rooms: 0, maxOccupancy: 0, color: '#64748B', iCalSourceUrl: '', active: true),
    );
    final branchColor = AppColors.branchColor(cleaning.branchId);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
        // 좌측 빨간 보더는 컬러바로 처리
      ),
      child: Row(
        children: [
          Container(
            width: 3, height: 36,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(2)),
          ),
          Container(
            constraints: const BoxConstraints(minWidth: 52),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: branchColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: Text(
              branch.name,
              style: TextStyle(color: branchColor, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('M/d (E)', 'ko').format(cleaning.scheduledDate),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 2),
                const Text('iCal 예약 · 미지정', style: TextStyle(color: AppColors.muted, fontSize: 11)),
              ],
            ),
          ),
          SizedBox(
            height: 32,
            child: FilledButton(
              onPressed: onAssign,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: const Text('배정'),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== 청소원 카드 =====

class _UserCard extends StatelessWidget {
  final UserModel user;
  const _UserCard({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: const BoxDecoration(color: AppColors.branch1, shape: BoxShape.circle),
            child: Center(
              child: Text(user.name[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(
                  user.isManager ? '매니저' : user.isChief ? '실장' : '청소원',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: user.active ? AppColors.ok : AppColors.dim,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
