import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';
import '../cleaning_detail/cleaning_detail_page.dart' show reservationProvider;
import '../shared/bottom_nav.dart';

/// ② 다가오는 청소 (홈) — 호점별로 가장 가까운 체크아웃 청소 표시
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    // 다가오는 청소 = 오늘부터 30일 이내, 체크아웃 날짜순
    final cleaningsAsync = ref.watch(upcomingCleaningsProvider);
    // 통계용: 오늘 청소만 별도
    final todayAsync = ref.watch(todayCleaningsProvider);
    final branchesAsync = ref.watch(branchesProvider);
    final branches = branchesAsync.valueOrNull ?? const <BranchModel>[];

    final today = DateFormat('M월 d일 (E)', 'ko').format(DateTime.now());

    return Scaffold(
      bottomNavigationBar: const AppBottomNav(active: BottomTab.home),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 상단 인사 + 매니저 버튼
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '안녕하세요, ${user?.name ?? ""}님',
                          style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w400),
                        ),
                        const SizedBox(height: 2),
                        Text(today, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  if (user?.canManageDashboard ?? false)
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.panel,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.dashboard_outlined, size: 20),
                        onPressed: () => context.push('/manager'),
                        tooltip: '매니저 대시보드',
                        color: AppColors.text,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),

              // 통계 카드 — 오늘 청소만 기준
              todayAsync.when(
                loading: () => const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('오류: $e', style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                ),
                data: (list) => _StatsRow(list: list),
              ),
              const SizedBox(height: 18),

              // 섹션 타이틀
              const _SectionTitle('다가오는 청소'),
              const SizedBox(height: 10),

              // 호점별 청소 목록
              Expanded(
                child: branchesAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        '호점 로드 실패: $e',
                        style: const TextStyle(color: AppColors.danger, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  data: (loadedBranches) {
                    if (loadedBranches.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.home_work_outlined, size: 44, color: AppColors.dim.withOpacity(0.5)),
                            const SizedBox(height: 10),
                            const Text(
                              '등록된 호점이 없습니다',
                              style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      );
                    }
                    return _BranchList(
                      branches: loadedBranches,
                      cleanings: cleaningsAsync.valueOrNull ?? const <CleaningModel>[],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 호점 목록 — 각 호점의 가장 가까운 다가오는 청소 1건 표시
class _BranchList extends StatelessWidget {
  final List<BranchModel> branches;
  final List<CleaningModel> cleanings; // 이미 scheduledDate 오름차순 정렬됨
  const _BranchList({required this.branches, required this.cleanings});

  @override
  Widget build(BuildContext context) {
    // 호점별로 가장 가까운 다가오는 청소 1건만 추출
    final Map<String, CleaningModel?> nearestByBranch = {};
    for (final b in branches) {
      nearestByBranch[b.id] = null;
    }
    for (final c in cleanings) {
      if (nearestByBranch.containsKey(c.branchId) && nearestByBranch[c.branchId] == null) {
        nearestByBranch[c.branchId] = c;
      }
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: branches.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final branch = branches[i];
        final nearest = nearestByBranch[branch.id];
        if (nearest == null) {
          return _EmptyBranchCard(branch: branch);
        }
        return _TaskCard(cleaning: nearest, branch: branch);
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final List<CleaningModel> list;
  const _StatsRow({required this.list});

  @override
  Widget build(BuildContext context) {
    final total = list.length;
    final done = list.where((c) => c.isCompleted).length;
    final remaining = total - done;
    return Row(
      children: [
        _statBox(total.toString(), '오늘 작업', AppColors.branch1, Icons.assignment_outlined),
        const SizedBox(width: 8),
        _statBox(done.toString(), '완료', AppColors.ok, Icons.check_circle_outline),
        const SizedBox(width: 8),
        _statBox(remaining.toString(), '남음', remaining > 0 ? AppColors.warn : AppColors.dim, Icons.pending_outlined),
      ],
    );
  }

  Widget _statBox(String num, String label, Color color, IconData icon) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 6),
              Text(num, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      );
}

/// 청소 일정이 있는 호점 카드
class _TaskCard extends ConsumerWidget {
  final CleaningModel cleaning;
  final BranchModel branch;
  const _TaskCard({required this.cleaning, required this.branch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchColor = AppColors.branchColor(cleaning.branchId);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isMine = user != null && cleaning.assigneeUid == user.uid;
    final reservationAsync = ref.watch(reservationProvider(cleaning.reservationId));
    final reservation = reservationAsync.valueOrNull;

    return Material(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => context.push('/cleaning/${cleaning.id}'),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 좌측 호점 컬러바
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: branchColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 호점 정보
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Text(branch.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _dateChipColor(cleaning.scheduledDate).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _dateLabel(cleaning.scheduledDate),
                                style: TextStyle(
                                  color: _dateChipColor(cleaning.scheduledDate),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (reservation != null)
                          Text(
                            '${reservation.guestName}님 · 👤 ${reservation.guestCount}인',
                            style: const TextStyle(fontSize: 13, color: AppColors.text, fontWeight: FontWeight.w600),
                          )
                        else
                          Text(
                            '체크아웃 ${DateFormat('M/d (E)', 'ko').format(cleaning.scheduledDate)}',
                            style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w500),
                          ),
                      ],
                    ),
                  ),
                ),
                // 상태 필 (세로 중앙 정렬)
                Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _statusPill(cleaning, isMine),
                  ),
                ),
                const Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Icon(Icons.chevron_right, color: AppColors.dim, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusPill(CleaningModel c, bool isMine) {
    if (c.isCompleted) return _pill('✓ 완료', AppColors.ok);
    if (c.isUnassigned) return _pill('미지정', AppColors.warn);
    if (isMine) return _pill('내 작업', AppColors.branch1);
    return _pill('진행중', AppColors.muted);
  }

  /// 날짜 라벨 ("오늘", "내일", "M/d")
  String _dateLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return '오늘';
    if (diff == 1) return '내일';
    if (diff < 0) return DateFormat('M/d', 'ko').format(d);
    if (diff <= 7) return 'D-$diff';
    return DateFormat('M/d', 'ko').format(d);
  }

  /// 날짜 칩 색상 (오늘=빨강, 내일=주황, 그 외=파랑)
  Color _dateChipColor(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return AppColors.danger;
    if (diff == 1) return AppColors.warn;
    return AppColors.branch1;
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      );
}

/// 청소 일정 없는 호점 카드 (호점만 표시)
class _EmptyBranchCard extends StatelessWidget {
  final BranchModel branch;
  const _EmptyBranchCard({required this.branch});

  @override
  Widget build(BuildContext context) {
    final branchColor = AppColors.branchColor(branch.id);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 좌측 호점 컬러바
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: branchColor.withOpacity(0.5),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      branch.name,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '다가오는 청소 없음',
                      style: TextStyle(fontSize: 13, color: AppColors.dim, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
            // 상태 필 (세로 중앙 정렬)
            Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.dim.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    '−',
                    style: TextStyle(color: AppColors.dim, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
