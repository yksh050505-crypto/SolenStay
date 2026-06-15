import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';
import 'manager_dashboard_widgets.dart';

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
///
/// 건수 증가에 견디는 구조:
///  - 상단 호점 필터 칩으로 모든 섹션을 동시에 좁힘
///  - 각 섹션은 접기/펼치기(CollapsibleSection) + 카운트 배지
///  - 리스트는 ShowMoreList로 초기 N개만 표시 후 "더보기"
///  - "지금 처리할 일"·"진행 중"은 날짜 그룹 헤더(오늘/내일/이후)로 묶음
class ManagerDashboardPage extends ConsumerStatefulWidget {
  const ManagerDashboardPage({super.key});

  @override
  ConsumerState<ManagerDashboardPage> createState() => _ManagerDashboardPageState();
}

class _ManagerDashboardPageState extends ConsumerState<ManagerDashboardPage> {
  /// 선택된 호점 필터(null = 전체)
  String? _branchFilter;

  List<CleaningModel> _applyFilter(List<CleaningModel> list) {
    if (_branchFilter == null) return list;
    return list.where((c) => c.branchId == _branchFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);

    if (userAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('매니저 대시보드'),
          leading: IconButton(icon: Icon(Icons.arrow_back), onPressed: () => context.pop()),
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final user = userAsync.value;
    if (user == null || !user.canManageDashboard) {
      return Scaffold(
        appBar: AppBar(
          title: Text('권한 없음'),
          leading: IconButton(icon: Icon(Icons.arrow_back), onPressed: () => context.pop()),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 48, color: context.brand.dim),
              SizedBox(height: 12),
              Text('매니저/실장만 접근 가능합니다', style: TextStyle(color: context.brand.muted)),
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
        title: Text('매니저 대시보드'),
        leading: IconButton(icon: Icon(Icons.arrow_back), onPressed: () => context.pop()),
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
                      Text('관리자', style: TextStyle(color: context.brand.muted, fontSize: 13)),
                      SizedBox(height: 2),
                      Text(
                        DateFormat('M월 d일 (E)', 'ko').format(DateTime.now()),
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 18),

            // 1) 큰 진행률 카드 (필터 무관 — 전체 진행률은 항상 표시)
            todayCleanings.when(
              loading: () => Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator())),
              error: (e, _) => Text('오류: $e'),
              data: (todayList) => _ProgressOverviewCard(
                todayList: todayList,
                branches: branches,
              ),
            ),
            SizedBox(height: 14),

            // 1.3) 호점 필터 칩 — 모든 섹션을 동시에 좁힘
            if (branches.isNotEmpty) ...[
              _BranchFilterBar(
                branches: branches,
                selected: _branchFilter,
                onChanged: (id) => setState(() => _branchFilter = id),
              ),
              SizedBox(height: 12),
            ],

            // 2) 지금 처리할 일 (미지정) — 기본 펼침 + 날짜 그룹
            unassigned.when(
              loading: () => const _SectionLoading(),
              error: (e, _) => _sectionError(e),
              data: (raw) {
                final list = _applyFilter(raw);
                return CollapsibleSection(
                  title: '지금 처리할 일',
                  danger: true,
                  count: list.length,
                  initiallyExpanded: list.isNotEmpty,
                  child: list.isEmpty
                      ? _emptyBox(
                          '모든 청소가 배정 완료!',
                          icon: Icons.check_circle_outline,
                          color: AppColors.ok,
                        )
                      : _DateGroupedList(
                          items: list,
                          dateOf: (c) => c.scheduledDate,
                          itemBuilder: (c) => _UnassignedCard(
                            cleaning: c,
                            branches: branches,
                            onAssign: () => _showAssignDialog(context, ref, c),
                          ),
                        ),
                );
              },
            ),

            // 3) 진행 중 청소 (배정됐지만 미완료) — 기본 접힘
            todayCleanings.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (raw) {
                final inProgress = _applyFilter(
                  raw.where((c) => !c.isCompleted && !c.isUnassigned).toList(),
                );
                return CollapsibleSection(
                  title: '진행 중',
                  leadingIcon: Icons.cleaning_services_outlined,
                  count: inProgress.length,
                  initiallyExpanded: false,
                  child: inProgress.isEmpty
                      ? _emptyBox('진행 중인 청소가 없습니다')
                      : _DateGroupedList(
                          items: inProgress,
                          dateOf: (c) => c.scheduledDate,
                          itemBuilder: (c) => _InProgressCard(cleaning: c, branches: branches),
                        ),
                );
              },
            ),

            // 4) 완료 보고 — 기본 접힘 + 요약 카운트, 펼치면 더보기
            completed.when(
              loading: () => const _SectionLoading(),
              error: (e, _) => _sectionError(e),
              data: (raw) {
                final list = _applyFilter(raw);
                return CollapsibleSection(
                  title: '완료 보고',
                  leadingIcon: Icons.check_circle_outline,
                  count: list.length,
                  initiallyExpanded: false,
                  child: list.isEmpty
                      ? _emptyBox('아직 완료 보고가 없습니다')
                      : ShowMoreList(
                          itemCount: list.length,
                          initialCount: 4,
                          itemBuilder: (ctx, i) =>
                              _CompletedReportCard(cleaning: list[i], branches: branches),
                        ),
                );
              },
            ),

            // 5) 특이사항 — 기본 접힘
            notes.when(
              loading: () => const _SectionLoading(),
              error: (e, _) => _sectionError(e),
              data: (raw) {
                final list = _applyFilter(raw);
                return CollapsibleSection(
                  title: '특이사항',
                  leadingIcon: Icons.sticky_note_2_outlined,
                  count: list.length,
                  initiallyExpanded: false,
                  child: list.isEmpty
                      ? _emptyBox('아직 등록된 특이사항이 없습니다')
                      : ShowMoreList(
                          itemCount: list.length,
                          initialCount: 4,
                          itemBuilder: (ctx, i) => _NoteCard(cleaning: list[i], branches: branches),
                        ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionError(Object e) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text('오류: $e', style: TextStyle(color: AppColors.danger)),
      );

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
          title: Text('사용자 추가'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 일괄 추가 빠른 버튼
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.brand.panel2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('일괄 추가 (PIN=000000)', style: TextStyle(fontSize: 11, color: context.brand.muted, fontWeight: FontWeight.w700)),
                      SizedBox(height: 6),
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
                              textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                              minimumSize: const Size(0, 28),
                            ),
                            child: Text('초기 6명 추가'),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        '박제인(매니저), 송현주(실장), 에블린·김소영·리첼·조은희(청소원)',
                        style: TextStyle(fontSize: 10, color: context.brand.dim),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 14),
                Text('또는 개별 추가', style: TextStyle(fontSize: 11, color: context.brand.muted, fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: '이름',
                    hintText: '예: 박제인',
                  ),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: pinCtrl,
                  decoration: InputDecoration(
                    labelText: '초기 PIN',
                  ),
                  keyboardType: TextInputType.number,
                ),
                SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: InputDecoration(labelText: '역할'),
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
              child: Text('취소'),
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
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('추가'),
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
            SizedBox(width: 8),
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
        title: Text('청소원 배정'),
        children: cleaners.map((u) => SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, u),
          child: Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: AppColors.branch1, shape: BoxShape.circle),
                child: Center(
                  child: Text(u.name[0], style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                ),
              ),
              SizedBox(width: 12),
              Text(u.name, style: TextStyle(fontSize: 14)),
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

// ===== 호점 필터 칩 바 =====

class _BranchFilterBar extends StatelessWidget {
  final List<BranchModel> branches;
  final String? selected;
  final ValueChanged<String?> onChanged;
  const _BranchFilterBar({required this.branches, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip({required String label, required bool active, required VoidCallback onTap, Color? color}) {
      final c = color ?? AppColors.branch1;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Material(
          color: active ? c.withOpacity(0.14) : context.brand.panel,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: active ? c : context.brand.line),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: active ? c : context.brand.muted,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip(
            label: '전체',
            active: selected == null,
            onTap: () => onChanged(null),
            color: context.brand.text,
          ),
          ...branches.map((b) => chip(
                label: b.name,
                active: selected == b.id,
                onTap: () => onChanged(b.id),
                color: AppColors.branchColor(b.id),
              )),
        ],
      ),
    );
  }
}

// ===== 섹션 로딩 플레이스홀더 =====

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
    );
  }
}

// ===== 날짜 그룹 + 더보기 결합 리스트 =====
//
// 항목을 오늘/내일/이번 주/이후 등으로 묶고, 각 그룹은 초기 N개만 표시 후 더보기.
class _DateGroupedList extends StatelessWidget {
  final List<CleaningModel> items;
  final DateTime Function(CleaningModel) dateOf;
  final Widget Function(CleaningModel) itemBuilder;
  static const int _initialPerGroup = 4;
  const _DateGroupedList({
    required this.items,
    required this.dateOf,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    // 그룹핑
    final groups = <String, List<CleaningModel>>{};
    for (final c in items) {
      final label = dateGroupLabel(dateOf(c));
      groups.putIfAbsent(label, () => []).add(c);
    }
    final orderedLabels = groups.keys.toList()
      ..sort((a, b) => dateGroupOrder(a).compareTo(dateGroupOrder(b)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final label in orderedLabels) ...[
          DateGroupHeader(label: label, count: groups[label]!.length),
          ShowMoreList(
            itemCount: groups[label]!.length,
            initialCount: _initialPerGroup,
            itemBuilder: (ctx, i) => itemBuilder(groups[label]![i]),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
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
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800),
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
          SizedBox(width: 20),
          // 우측: 호점별 막대 + 라벨
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '오늘 청소 진행률',
                  style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 10),
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
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
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
                        SizedBox(width: 8),
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
        color: context.brand.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.brand.line),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 38,
            decoration: BoxDecoration(color: branchColor, borderRadius: BorderRadius.circular(2)),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(branch.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.branch1.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        assigneeName,
                        style: TextStyle(color: AppColors.branch1, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  '진행 중 · $progressTxt',
                  style: TextStyle(color: context.brand.muted, fontSize: 11),
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
                  backgroundColor: context.brand.line,
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
        _statCard('$checkOuts', '오늘 체크아웃', sub: '1·2·3호점', color: context.brand.text),
        _statCard('$checkIns', '오늘 체크인', sub: '예약 기준', color: context.brand.text),
        _statCard('$completed', '청소 완료', sub: '진행 ${checkOuts - completed}건', color: AppColors.ok),
        _statCard(
          '$unassigned',
          '미지정 청소',
          sub: unassigned > 0 ? '⚠ 확인 필요' : '없음',
          color: unassigned > 0 ? AppColors.danger : context.brand.muted,
          subColor: unassigned > 0 ? AppColors.danger : context.brand.muted,
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
          SizedBox(height: 2),
          Text(label, style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600)),
          if (sub != null) ...[
            SizedBox(height: 4),
            Text(sub, style: TextStyle(color: subColor ?? AppColors.muted, fontSize: 10)),
          ],
        ],
      ),
    );
  }
}

// ===== 완료 보고 이동: 대상 청소 선택 다이얼로그 =====
//
// 후보가 많아도 길어지지 않도록: 고정 높이 + 스크롤 + 게스트/날짜 검색 + 날짜 그룹 헤더.
class _TransferTargetPicker extends StatefulWidget {
  final String branchName;
  final String who;
  final int photoCount;
  final List<CleaningModel> candidates;
  final Map<String, String> guestByRes;
  const _TransferTargetPicker({
    required this.branchName,
    required this.who,
    required this.photoCount,
    required this.candidates,
    required this.guestByRes,
  });

  @override
  State<_TransferTargetPicker> createState() => _TransferTargetPickerState();
}

class _TransferTargetPickerState extends State<_TransferTargetPicker> {
  String _query = '';

  String _guestOf(CleaningModel c) => widget.guestByRes[c.reservationId] ?? '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.candidates
        : widget.candidates.where((c) {
            final guest = _guestOf(c).toLowerCase();
            final dateStr = DateFormat('M/d (E)', 'ko').format(c.scheduledDate).toLowerCase();
            final who = (c.assigneeName ?? '').toLowerCase();
            return guest.contains(q) || dateStr.contains(q) || who.contains(q);
          }).toList();

    // 날짜 그룹핑
    final groups = <String, List<CleaningModel>>{};
    for (final c in filtered) {
      final label = dateGroupLabel(c.scheduledDate);
      groups.putIfAbsent(label, () => []).add(c);
    }
    final orderedLabels = groups.keys.toList()
      ..sort((a, b) => dateGroupOrder(a).compareTo(dateGroupOrder(b)));

    final size = MediaQuery.of(context).size;
    final maxH = size.height * 0.6;

    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH, maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('올바른 청소 선택 · ${widget.branchName}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    '“${widget.who}”의 완료 보고(사진 ${widget.photoCount}장)를 옮길 청소를 고르세요',
                    style: TextStyle(fontSize: 12, color: context.brand.muted),
                  ),
                ],
              ),
            ),
            // 검색
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: '게스트명·날짜로 검색',
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            // 후보 리스트 (스크롤)
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text('검색 결과가 없습니다',
                            style: TextStyle(color: context.brand.muted, fontSize: 13)),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      children: [
                        for (final label in orderedLabels) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                            child: DateGroupHeader(label: label, count: groups[label]!.length),
                          ),
                          ...groups[label]!.map((c) {
                            final guest = _guestOf(c);
                            final dateStr = DateFormat('M/d (E)', 'ko').format(c.scheduledDate);
                            final statusKo = c.isUnassigned
                                ? '미배정'
                                : (c.assigneeName?.isNotEmpty == true ? c.assigneeName! : '배정됨');
                            return InkWell(
                              onTap: () => Navigator.pop(context, c),
                              borderRadius: BorderRadius.circular(10),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 64,
                                      child: Text(dateStr,
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                    ),
                                    Expanded(
                                      child: Text(
                                        guest.isNotEmpty ? guest : '(게스트 미상)',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    Text(statusKo,
                                        style: TextStyle(fontSize: 11, color: context.brand.muted)),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
            ),
            // 취소
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== 완료 보고 카드 =====

class _CompletedReportCard extends ConsumerWidget {
  final CleaningModel cleaning;
  final List<BranchModel> branches;
  const _CompletedReportCard({required this.cleaning, required this.branches});

  /// 완료 보고를 올바른 청소로 이동(transfer) — 청소원이 엉뚱한 청소를 완료 보고했을 때,
  /// 매니저가 사진·메모·완료시각을 '실제로 한 청소'로 옮긴다.
  ///  - 대상(target): 완료처리 + 이 카드(source)의 사진/메모/완료시각/체크리스트(전체체크) 복사,
  ///                  담당자는 대상에 이미 있으면 유지, 없으면 source의 담당자로 설정
  ///  - 원본(source): 미배정으로 복구 + 사진/메모/완료/담당 제거 (다시 정상 처리 가능)
  /// 두 문서를 batch로 원자적 수정. (firestore.rules가 매니저 직접 수정 허용)
  Future<void> _transferToCorrectCleaning(BuildContext context, WidgetRef ref) async {
    final db = ref.read(firestoreProvider);
    final branch = branches.firstWhere(
      (b) => b.id == cleaning.branchId,
      orElse: () => BranchModel(id: cleaning.branchId, name: cleaning.branchId, rooms: 0, maxOccupancy: 0, color: '#64748B', iCalSourceUrl: '', active: true),
    );
    final who = cleaning.assigneeName?.isNotEmpty == true ? cleaning.assigneeName! : '청소원';

    // 후보 청소 + 게스트명 조회 (같은 호점, 미완료, 원본 날짜 ±45일)
    List<CleaningModel> candidates;
    final guestByRes = <String, String>{};
    try {
      final lo = cleaning.scheduledDate.subtract(const Duration(days: 45));
      final hi = cleaning.scheduledDate.add(const Duration(days: 45));
      final cSnap = await db.collection('cleanings').where('branchId', isEqualTo: cleaning.branchId).get();
      candidates = cSnap.docs
          .map(CleaningModel.fromDoc)
          .where((c) => c.id != cleaning.id && !c.isCompleted &&
              c.scheduledDate.isAfter(lo) && c.scheduledDate.isBefore(hi))
          .toList()
        ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
      final rSnap = await db.collection('reservations').where('branchId', isEqualTo: cleaning.branchId).get();
      for (final d in rSnap.docs) {
        final r = ReservationModel.fromDoc(d);
        guestByRes[r.id] = r.guestName;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('후보 조회 실패: $e'), backgroundColor: AppColors.danger),
        );
      }
      return;
    }
    if (!context.mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이동할 대상 청소가 없습니다 (같은 호점·미완료)')),
      );
      return;
    }

    // 대상 선택 — 스크롤 가능한 제한 높이 + 검색 + 날짜 그룹
    final target = await showDialog<CleaningModel>(
      context: context,
      builder: (ctx) => _TransferTargetPicker(
        branchName: branch.name,
        who: who,
        photoCount: cleaning.photoUrls.length,
        candidates: candidates,
        guestByRes: guestByRes,
      ),
    );
    if (target == null || !context.mounted) return;

    // 확인
    final tgtDateStr = DateFormat('M/d (E)', 'ko').format(target.scheduledDate);
    final tgtGuest = guestByRes[target.reservationId] ?? '';
    final srcDateStr = DateFormat('M/d (E)', 'ko').format(cleaning.scheduledDate);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('완료 보고 이동'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('완료 보고(사진 ${cleaning.photoUrls.length}장)를 아래로 이동합니다.', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            Text('FROM  $srcDateStr · $who', style: TextStyle(color: context.brand.muted, decoration: TextDecoration.lineThrough)),
            const SizedBox(height: 2),
            Text('TO      $tgtDateStr · ${tgtGuest.isNotEmpty ? tgtGuest : target.branchId}', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            const Text('대상은 완료처리되고, 원본은 미배정으로 복구됩니다. 예약 정보는 바뀌지 않습니다.', style: TextStyle(fontSize: 12, height: 1.4)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('이동')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final batch = db.batch();
      // 대상 → 완료처리 (source의 결과 복사)
      batch.update(db.collection('cleanings').doc(target.id), {
        'status': 'completed',
        'photoUrls': cleaning.photoUrls,
        'memo': cleaning.memo,
        'completedAt': cleaning.completedAt != null
            ? Timestamp.fromDate(cleaning.completedAt!)
            : FieldValue.serverTimestamp(),
        'checklist': target.checklist.map((i) => i.copyWith(checked: true).toMap()).toList(),
        'assigneeUid': target.assigneeUid ?? cleaning.assigneeUid,
        'assigneeName': target.assigneeName ?? cleaning.assigneeName,
      });
      // 원본 → 미배정 복구
      batch.update(db.collection('cleanings').doc(cleaning.id), {
        'status': 'unassigned',
        'assigneeUid': null,
        'assigneeName': null,
        'photoUrls': <String>[],
        'memo': '',
        'completedAt': FieldValue.delete(),
        'nextGuestSnapshot': FieldValue.delete(),
        'checklist': cleaning.checklist.map((i) => i.copyWith(checked: false).toMap()).toList(),
      });
      await batch.commit();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('완료 보고를 $tgtDateStr 청소로 이동했습니다'), backgroundColor: AppColors.ok),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('이동 실패: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManager = ref.watch(currentUserProvider).value?.isManager ?? false;
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
      color: context.brand.panel,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => context.push('/cleaning/${cleaning.id}/complete'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.brand.line),
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
                  SizedBox(width: 8),
                  Icon(Icons.check_circle, size: 14, color: AppColors.ok),
                  SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '$assigneeName · $completedStr',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 사진 개수 표시 (실제 사진은 카드 탭 시 상세에서 확인)
                  if (photoCount > 0) ...[
                    Icon(Icons.photo_library_outlined, size: 13, color: context.brand.muted),
                    SizedBox(width: 3),
                    Text(
                      '$photoCount',
                      style: TextStyle(color: context.brand.muted, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(width: 6),
                  ],
                  // 완료 보고를 올바른 청소로 이동 — 매니저 전용
                  if (isManager) ...[
                    InkWell(
                      onTap: () => _transferToCorrectCleaning(context, ref),
                      borderRadius: BorderRadius.circular(99),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.swap_horiz, size: 18, color: AppColors.branch1),
                      ),
                    ),
                    SizedBox(width: 2),
                  ],
                  Icon(Icons.chevron_right, color: context.brand.dim, size: 18),
                ],
              ),
              // 메모
              if (hasMemo) ...[
                SizedBox(height: 8),
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
                      Icon(Icons.sticky_note_2_outlined, size: 14, color: AppColors.warn),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          cleaning.memo,
                          style: TextStyle(fontSize: 12, color: context.brand.text, height: 1.4),
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
        color: context.brand.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.brand.line),
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
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$assigneeName · $dateStr',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                    ),
                    if (cleaning.photoUrls.isNotEmpty)
                      Text(
                        '📷 ${cleaning.photoUrls.length}',
                        style: TextStyle(color: context.brand.muted, fontSize: 11),
                      ),
                  ],
                ),
                SizedBox(height: 4),
                Text(
                  cleaning.memo,
                  style: TextStyle(fontSize: 12, color: context.brand.text, height: 1.4),
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
        color: context.brand.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.brand.line),
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
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('M/d (E)', 'ko').format(cleaning.scheduledDate),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                SizedBox(height: 2),
                Text('iCal 예약 · 미지정', style: TextStyle(color: context.brand.muted, fontSize: 11)),
              ],
            ),
          ),
          SizedBox(
            height: 32,
            child: FilledButton(
              onPressed: onAssign,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: TextStyle(fontSize: 12),
              ),
              child: Text('배정'),
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
        color: context.brand.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.brand.line),
      ),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: AppColors.branch1, shape: BoxShape.circle),
            child: Center(
              child: Text(user.name[0], style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(
                  user.isManager ? '매니저' : user.isChief ? '실장' : '청소원',
                  style: TextStyle(color: context.brand.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: user.active ? AppColors.ok : context.brand.dim,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
