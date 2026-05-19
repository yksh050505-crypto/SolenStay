import 'package:cached_network_image/cached_network_image.dart';
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

/// 완료 보고 Provider — 최근 완료된 청소 전체 (메모 유무 무관)
final recentCompletedProvider = StreamProvider<List<CleaningModel>>((ref) {
  final authUser = ref.watch(firebaseUserProvider).value;
  if (authUser == null) return Stream.value(const <CleaningModel>[]);

  return ref
      .watch(firestoreProvider)
      .collection('cleanings')
      .where('status', isEqualTo: 'completed')
      .orderBy('completedAt', descending: true)
      .limit(20)
      .snapshots()
      .map((s) => s.docs.map(CleaningModel.fromDoc).toList());
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
    final completed = ref.watch(recentCompletedProvider);

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

            // 1) 큰 진행률 카드
            todayCleanings.when(
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
              error: (e, _) => Text('오류: $e'),
              data: (todayList) => _ProgressOverviewCard(
                todayList: todayList,
                branches: branches,
              ),
            ),
            const SizedBox(height: 18),

            // 1.5) 완료 보고 — 최근 청소 완료 내역 (사진 포함)
            _SectionHeader(title: '완료 보고'),
            const SizedBox(height: 10),
            completed.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('오류: $e', style: const TextStyle(color: AppColors.danger)),
              data: (list) {
                if (list.isEmpty) {
                  return _emptyBox('아직 완료 보고가 없습니다');
                }
                return Column(
                  children: list.take(10).map((c) => _CompletedReportCard(cleaning: c, branches: branches)).toList(),
                );
              },
            ),
            const SizedBox(height: 18),

            // 2) 지금 처리할 일 (미지정 청소 + 임박)
            _SectionHeader(title: '지금 처리할 일', danger: true),
            const SizedBox(height: 10),
            unassigned.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('오류: $e', style: const TextStyle(color: AppColors.danger)),
              data: (list) {
                final urgent = list.take(5).toList();
                if (urgent.isEmpty) {
                  return _emptyBox(
                    '모든 청소가 배정 완료!',
                    icon: Icons.check_circle_outline,
                    color: AppColors.ok,
                  );
                }
                return Column(
                  children: urgent.map((c) => _UnassignedCard(
                    cleaning: c,
                    branches: branches,
                    onAssign: () => _showAssignDialog(context, ref, c),
                  )).toList(),
                );
              },
            ),
            const SizedBox(height: 18),

            // 3) 진행 중 청소 (배정됐지만 미완료)
            todayCleanings.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (list) {
                final inProgress = list.where((c) => !c.isCompleted && !c.isUnassigned).toList();
                if (inProgress.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SectionHeader(title: '진행 중'),
                    const SizedBox(height: 10),
                    ...inProgress.map((c) => _InProgressCard(cleaning: c, branches: branches)),
                    const SizedBox(height: 18),
                  ],
                );
              },
            ),

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
            const SizedBox(height: 4),

            // (옛 "청소 일정 미입력" 섹션은 상단 "지금 처리할 일"로 통합)

            // (사용자 섹션 제거됨 - 관리자 설정에만 있음)
          ],
        ),
      ),
    );
  }

  /// 사용자 추가 다이얼로그
  Future<void> _showAddUserDialog(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final pinCtrl = TextEditingController(text: '000000');
    String role = 'cleaner';
    bool loading = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('사용자 추가'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 일괄 추가 빠른 버튼
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.panel2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('일괄 추가 (PIN=000000)', style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          FilledButton(
                            onPressed: loading ? null : () async {
                              setState(() => loading = true);
                              await _batchAddInitialUsers(context, ref);
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                              minimumSize: const Size(0, 28),
                            ),
                            child: const Text('초기 6명 추가'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '박제인(매니저), 송현주(실장), 에블린·김소영·리첼·조은희(청소원)',
                        style: TextStyle(fontSize: 10, color: AppColors.dim),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text('또는 개별 추가', style: TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '이름',
                    hintText: '예: 박제인',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: pinCtrl,
                  decoration: const InputDecoration(
                    labelText: '초기 PIN',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(labelText: '역할'),
                  items: const [
                    DropdownMenuItem(value: 'cleaner', child: Text('청소원')),
                    DropdownMenuItem(value: 'chief', child: Text('실장')),
                    DropdownMenuItem(value: 'manager', child: Text('매니저')),
                  ],
                  onChanged: (v) => setState(() => role = v ?? 'cleaner'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      final pin = pinCtrl.text.trim();
                      if (name.isEmpty || pin.length < 4) return;
                      setState(() => loading = true);
                      try {
                        await ref.read(functionsServiceProvider).registerUser(
                              name: name,
                              pin: pin,
                              role: role,
                            );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$name ($role) 추가됨'), backgroundColor: AppColors.ok),
                          );
                        }
                      } catch (e) {
                        setState(() => loading = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('추가 실패: $e')));
                        }
                      }
                    },
              child: loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('추가'),
            ),
          ],
        ),
      ),
    );
  }

  /// 초기 6명 일괄 추가
  Future<void> _batchAddInitialUsers(BuildContext context, WidgetRef ref) async {
    final users = [
      ('박제인', 'manager'),
      ('송현주', 'chief'),
      ('에블린', 'cleaner'),
      ('김소영', 'cleaner'),
      ('리첼', 'cleaner'),
      ('조은희', 'cleaner'),
    ];

    final fn = ref.read(functionsServiceProvider);
    int added = 0;
    final errors = <String>[];

    for (final (name, role) in users) {
      try {
        await fn.registerUser(name: name, pin: '000000', role: role);
        added++;
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('already-exists') || msg.contains('already')) {
          // 이미 존재 — 스킵
        } else {
          errors.add('$name: $e');
        }
      }
    }

    if (context.mounted) {
      if (errors.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$added명 추가 완료 (이미 있는 사용자는 스킵)'), backgroundColor: AppColors.ok),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$added명 추가 / 실패 ${errors.length}건')),
        );
      }
    }
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

// ===== 큰 진행률 카드 (도넛 + 호점별 막대) =====

class _ProgressOverviewCard extends StatelessWidget {
  final List<CleaningModel> todayList;
  final List<BranchModel> branches;
  const _ProgressOverviewCard({required this.todayList, required this.branches});

  @override
  Widget build(BuildContext context) {
    final total = todayList.length;
    final done = todayList.where((c) => c.isCompleted).length;
    final pct = total > 0 ? done / total : 0.0;
    final pctInt = (pct * 100).round();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.branch1, AppColors.branch1.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 좌측: 도넛 차트
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 10,
                    backgroundColor: Colors.white.withOpacity(0.25),
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$pctInt%',
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '$done/$total',
                      style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          // 우측: 호점별 막대 + 라벨
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '오늘 청소 진행률',
                  style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                ...branches.map((b) {
                  final bList = todayList.where((c) => c.branchId == b.id).toList();
                  final bTotal = bList.length;
                  final bDone = bList.where((c) => c.isCompleted).length;
                  final bPct = bTotal > 0 ? bDone / bTotal : 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 36,
                          child: Text(
                            b.name,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: bPct,
                              minHeight: 6,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 28,
                          child: Text(
                            bTotal > 0 ? '$bDone/$bTotal' : '−',
                            textAlign: TextAlign.right,
                            style: TextStyle(color: Colors.white.withOpacity(0.95), fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===== 진행 중 청소 카드 =====

class _InProgressCard extends StatelessWidget {
  final CleaningModel cleaning;
  final List<BranchModel> branches;
  const _InProgressCard({required this.cleaning, required this.branches});

  @override
  Widget build(BuildContext context) {
    final branch = branches.firstWhere(
      (b) => b.id == cleaning.branchId,
      orElse: () => BranchModel(id: cleaning.branchId, name: cleaning.branchId, rooms: 0, maxOccupancy: 0, color: '#64748B', iCalSourceUrl: '', active: true),
    );
    final branchColor = AppColors.branchColor(cleaning.branchId);
    // denormalize된 assigneeName 사용 (users 컬렉션 읽지 않음)
    final assigneeName = cleaning.assigneeName?.isNotEmpty == true ? cleaning.assigneeName! : '담당자';

    final progressTxt = cleaning.checklist.isEmpty
        ? '−'
        : '${cleaning.checkedCount}/${cleaning.checklist.length} 항목';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 38,
            decoration: BoxDecoration(color: branchColor, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(branch.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.branch1.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        assigneeName,
                        style: const TextStyle(color: AppColors.branch1, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '진행 중 · $progressTxt',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          if (cleaning.checklist.isNotEmpty)
            SizedBox(
              width: 60,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: cleaning.checkedCount / cleaning.checklist.length,
                  minHeight: 6,
                  backgroundColor: AppColors.line,
                  valueColor: AlwaysStoppedAnimation<Color>(branchColor),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ===== (옛) 2x2 통계 카드 — 더 이상 사용 안함, 호환용 유지 =====

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

// ===== 완료 보고 카드 =====

class _CompletedReportCard extends StatelessWidget {
  final CleaningModel cleaning;
  final List<BranchModel> branches;
  const _CompletedReportCard({required this.cleaning, required this.branches});

  @override
  Widget build(BuildContext context) {
    final branch = branches.firstWhere(
      (b) => b.id == cleaning.branchId,
      orElse: () => BranchModel(id: cleaning.branchId, name: cleaning.branchId, rooms: 0, maxOccupancy: 0, color: '#64748B', iCalSourceUrl: '', active: true),
    );
    final branchColor = AppColors.branchColor(cleaning.branchId);
    final assigneeName = cleaning.assigneeName?.isNotEmpty == true ? cleaning.assigneeName! : '청소원';
    final completedAt = cleaning.completedAt;
    final completedStr = completedAt != null
        ? DateFormat('M/d (E) HH:mm', 'ko').format(completedAt)
        : DateFormat('M/d (E)', 'ko').format(cleaning.scheduledDate);
    final hasMemo = cleaning.memo.isNotEmpty;
    final photoCount = cleaning.photoUrls.length;

    return Material(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => context.push('/cleaning/${cleaning.id}/complete'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단: 호점 배지 + 완료 정보
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
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
                  const SizedBox(width: 8),
                  const Icon(Icons.check_circle, size: 14, color: AppColors.ok),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '$assigneeName · $completedStr',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.dim, size: 18),
                ],
              ),
              // 사진 썸네일 영역
              if (photoCount > 0) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: cleaning.photoUrls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: cleaning.photoUrls[i],
                        width: 84,
                        height: 84,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          width: 84, height: 84, color: AppColors.line,
                          alignment: Alignment.center,
                          child: const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 84, height: 84, color: AppColors.line,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined, size: 20, color: AppColors.dim),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              // 메모
              if (hasMemo) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warn.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.warn.withOpacity(0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.sticky_note_2_outlined, size: 14, color: AppColors.warn),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          cleaning.memo,
                          style: const TextStyle(fontSize: 12, color: AppColors.text, height: 1.4),
                          maxLines: 3, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ===== 특이사항 카드 =====

class _NoteCard extends StatelessWidget {
  final CleaningModel cleaning;
  final List<BranchModel> branches;
  const _NoteCard({required this.cleaning, required this.branches});

  @override
  Widget build(BuildContext context) {
    final branch = branches.firstWhere(
      (b) => b.id == cleaning.branchId,
      orElse: () => BranchModel(id: cleaning.branchId, name: cleaning.branchId, rooms: 0, maxOccupancy: 0, color: '#64748B', iCalSourceUrl: '', active: true),
    );
    final branchColor = AppColors.branchColor(cleaning.branchId);
    final assigneeName = cleaning.assigneeName?.isNotEmpty == true ? cleaning.assigneeName! : '청소원';
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
