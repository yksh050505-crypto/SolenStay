import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';
import '../cleaning_detail/cleaning_detail_page.dart' show reservationProvider;
import '../shared/bottom_nav.dart';
import '../shared/notification_bell.dart';
import '../update/update_checker.dart';

/// ② 다가오는 청소 (홈) — 호점별로 가장 가까운 체크아웃 청소 표시
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).valueOrNull;
    // 다가오는 청소 = 오늘부터 30일 이내, 체크아웃 날짜순
    final cleaningsAsync = ref.watch(upcomingCleaningsProvider);
    // 통계용: 오늘 청소만 별도
    final branchesAsync = ref.watch(branchesProvider);
    final branches = branchesAsync.valueOrNull ?? const <BranchModel>[];

    final today = DateFormat('M월 d일 (E)', 'ko').format(DateTime.now());

    return Scaffold(
      bottomNavigationBar: const AppBottomNav(active: BottomTab.home),
      body: SafeArea(
        child: Stack(children: [
          // 화면에는 보이지 않지만, 마운트되면 한 번만 새 버전을 체크
          const UpdateChecker(),
          Padding(
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
                          style: TextStyle(color: context.brand.muted, fontSize: 13, fontWeight: FontWeight.w400),
                        ),
                        SizedBox(height: 2),
                        Text(today, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  // 알림 버튼 (모든 사용자) + 미읽 뱃지
                  const NotificationBellButton(),
                ],
              ),
              SizedBox(height: 18),

              // 미배정 청소 배너 (연간)
              const _UnassignedBanner(),
              SizedBox(height: 18),

              // 매니저: 호점별 / 실장·청소원: 타임라인
              Expanded(
                child: branchesAsync.when(
                  loading: () => Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        '호점 로드 실패: $e',
                        style: TextStyle(color: AppColors.danger, fontSize: 12),
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
                            Icon(Icons.home_work_outlined, size: 44, color: context.brand.dim.withOpacity(0.5)),
                            SizedBox(height: 10),
                            Text(
                              '등록된 호점이 없습니다',
                              style: TextStyle(color: context.brand.muted, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      );
                    }
                    final isManager = user?.isManager ?? false;
                    final allCleanings = cleaningsAsync.valueOrNull ?? const <CleaningModel>[];

                    if (isManager) {
                      // 매니저: 전체 운영 관점 — 이번 달 요약 + 호점별 현황 + 미배정 처리
                      return _ManagerHomeView(
                        branches: loadedBranches,
                        allCleanings: allCleanings,
                      );
                    }

                    // 청소원·실장:
                    //  - "오늘의 청소" 섹션: 자기에게 배정된 오늘 작업
                    //  - "다가오는 청소" 섹션: 호점별 가장 가까운 청소 1건씩 (1·2·3호점 다)
                    return _CleanerHomeView(
                      branches: loadedBranches,
                      allCleanings: allCleanings,
                      uid: user?.uid,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        ]),
      ),
    );
  }
}

/// 청소원·실장 홈 뷰 — 상단 "오늘의 청소"(자기 작업) + 하단 "다가오는 청소"(호점별 1·2·3호점)
class _CleanerHomeView extends ConsumerWidget {
  final List<BranchModel> branches;
  final List<CleaningModel> allCleanings;
  final String? uid;
  const _CleanerHomeView({
    required this.branches,
    required this.allCleanings,
    required this.uid,
  });

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservations = ref.watch(upcomingReservationsProvider).valueOrNull ?? const <ReservationModel>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 입실 게스트 매칭 (청소일 이후 같은 호점에서 가장 가까운 입실 예약)
    ReservationModel? incomingOf(CleaningModel c) {
      final cd = DateTime(c.scheduledDate.year, c.scheduledDate.month, c.scheduledDate.day);
      ReservationModel? best;
      for (final r in reservations) {
        if (r.branchId != c.branchId) continue;
        final inDay = DateTime(r.checkIn.year, r.checkIn.month, r.checkIn.day);
        if (inDay.isBefore(cd)) continue;
        if (best == null || r.checkIn.isBefore(best.checkIn)) best = r;
      }
      return best;
    }

    // 오늘의 청소 = 내 배정 && 오늘 && 완료 아님
    final todayMine = uid == null
        ? const <CleaningModel>[]
        : allCleanings.where((c) {
            final d = DateTime(c.scheduledDate.year, c.scheduledDate.month, c.scheduledDate.day);
            return c.assigneeUid == uid && !c.isCompleted && _sameDay(d, today);
          }).toList();

    // 다가오는 청소 = 내 배정 && 미래(내일+) && 완료 아님, 날짜 오름차순
    final upcomingMine = uid == null
        ? const <CleaningModel>[]
        : (allCleanings.where((c) {
            final d = DateTime(c.scheduledDate.year, c.scheduledDate.month, c.scheduledDate.day);
            return c.assigneeUid == uid && !c.isCompleted && d.isAfter(today);
          }).toList()
            ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate)));

    // 완료한 작업 = 내 배정 && 완료, 최신순 (완료시각 → 없으면 청소일 기준). 최근 30건.
    final completedMine = uid == null
        ? const <CleaningModel>[]
        : (allCleanings.where((c) => c.assigneeUid == uid && c.isCompleted).toList()
              ..sort((a, b) {
                final ad = a.completedAt ?? a.scheduledDate;
                final bd = b.completedAt ?? b.scheduledDate;
                return bd.compareTo(ad);
              }))
            .take(30)
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionTitle('오늘의 청소'),
        SizedBox(height: 10),
        if (todayMine.isEmpty)
          _EmptyAssignmentCard(text: '오늘 배정된 청소가 없습니다')
        else
          ...todayMine.map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CleaningTaskCard(item: _TaskItem(cleaning: c, incoming: incomingOf(c)), branches: branches),
              )),
        SizedBox(height: 22),
        // 다가오는 청소 + 완료한 작업 — 함께 스크롤
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const _SectionTitle('다가오는 청소'),
              SizedBox(height: 10),
              if (upcomingMine.isEmpty)
                _EmptyAssignmentCard(text: '배정된 청소가 없습니다')
              else
                ...upcomingMine.map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CleaningTaskCard(
                        item: _TaskItem(cleaning: c, incoming: incomingOf(c)),
                        branches: branches,
                      ),
                    )),
              SizedBox(height: 22),
              // 완료한 작업 — 기본 접힘(접이식). 탭하면 펼쳐짐.
              _CompletedTasksSection(
                items: completedMine
                    .map((c) => _TaskItem(cleaning: c, incoming: incomingOf(c)))
                    .toList(),
                branches: branches,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 완료한 작업 — 접이식 섹션 (기본 접힘). 헤더 탭으로 펼침/접힘.
class _CompletedTasksSection extends StatefulWidget {
  final List<_TaskItem> items;
  final List<BranchModel> branches;
  const _CompletedTasksSection({required this.items, required this.branches});

  @override
  State<_CompletedTasksSection> createState() => _CompletedTasksSectionState();
}

class _CompletedTasksSectionState extends State<_CompletedTasksSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.items.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 헤더 (탭하면 펼침/접힘)
        Material(
          color: context.brand.panel,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.brand.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 18, color: AppColors.ok),
                  SizedBox(width: 8),
                  Text('완료한 작업', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.ok.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(color: AppColors.ok, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Spacer(),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: context.brand.muted),
                ],
              ),
            ),
          ),
        ),
        if (_expanded) ...[
          SizedBox(height: 8),
          if (widget.items.isEmpty)
            _EmptyAssignmentCard(text: '완료한 작업이 없습니다')
          else
            ...widget.items.map((it) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CleaningTaskCard(item: it, branches: widget.branches),
                )),
        ],
      ],
    );
  }
}

/// 빈 상태 카드 — "배정된 청소가 없습니다"
class _EmptyAssignmentCard extends StatelessWidget {
  final String text;
  const _EmptyAssignmentCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? context.brand.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerTheme.color ?? context.brand.line),
      ),
      child: Center(
        child: Text(text, style: TextStyle(color: context.brand.muted, fontSize: 13)),
      ),
    );
  }
}

/// 실장/청소원 전용 — 오늘의 청소 / 다가오는 청소(7일 이내) [구버전, 미사용]
class _TimelineView extends ConsumerWidget {
  final List<BranchModel> branches;
  final List<CleaningModel> cleanings; // 이미 scheduledDate 오름차순
  const _TimelineView({required this.branches, required this.cleanings});

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservations = ref.watch(upcomingReservationsProvider).valueOrNull ?? const <ReservationModel>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekEnd = today.add(const Duration(days: 7));

    // 입실 게스트 매칭: 같은 호점에서 청소일 이후 가장 가까운 입실 예약
    ReservationModel? incomingOf(CleaningModel c) {
      final cd = DateTime(c.scheduledDate.year, c.scheduledDate.month, c.scheduledDate.day);
      ReservationModel? best;
      for (final r in reservations) {
        if (r.branchId != c.branchId) continue;
        final inDay = DateTime(r.checkIn.year, r.checkIn.month, r.checkIn.day);
        if (inDay.isBefore(cd)) continue;
        if (best == null || r.checkIn.isBefore(best.checkIn)) best = r;
      }
      return best;
    }

    // 오늘 / 다가오는(내일 ~ +7일) 분리
    final todays = <_TaskItem>[];
    final upcoming = <_TaskItem>[];
    for (final c in cleanings) {
      final d = DateTime(c.scheduledDate.year, c.scheduledDate.month, c.scheduledDate.day);
      if (d.isBefore(today)) continue;
      if (d.isAfter(weekEnd)) break; // cleanings already sorted asc
      final item = _TaskItem(cleaning: c, incoming: incomingOf(c));
      if (_sameDay(d, today)) {
        todays.add(item);
      } else {
        upcoming.add(item);
      }
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const _SectionTitle('오늘의 청소'),
        SizedBox(height: 10),
        if (todays.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: context.brand.panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.brand.line),
            ),
            child: Center(
              child: Text('오늘 청소가 없습니다', style: TextStyle(color: context.brand.muted, fontSize: 13)),
            ),
          )
        else
          ...todays.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CleaningTaskCard(item: t, branches: branches),
              )),
        SizedBox(height: 22),
        const _SectionTitle('다가오는 청소'),
        SizedBox(height: 10),
        if (upcoming.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: context.brand.panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.brand.line),
            ),
            child: Center(
              child: Text('7일 이내 예정된 청소가 없습니다', style: TextStyle(color: context.brand.muted, fontSize: 13)),
            ),
          )
        else
          ...upcoming.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CleaningTaskCard(item: t, branches: branches),
              )),
        SizedBox(height: 20),
      ],
    );
  }
}

class _TaskItem {
  final CleaningModel cleaning;
  final ReservationModel? incoming; // 입실 게스트 (있으면)
  _TaskItem({required this.cleaning, required this.incoming});
}

/// 청소 카드 — 호점 색상 + 입실 게스트 정보 + 실제 날짜
class _CleaningTaskCard extends ConsumerWidget {
  final _TaskItem item;
  final List<BranchModel> branches;
  const _CleaningTaskCard({required this.item, required this.branches});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = item.cleaning;
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isMine = user != null && c.assigneeUid == user.uid;
    final branch = branches.firstWhere(
      (b) => b.id == c.branchId,
      orElse: () => BranchModel(id: c.branchId, name: c.branchId, rooms: 0, maxOccupancy: 0, color: '#64748B', iCalSourceUrl: '', active: true),
    );
    final color = AppColors.branchColor(c.branchId);
    final dateStr = DateFormat('M/d (E)', 'ko').format(c.scheduledDate);

    final incoming = item.incoming;
    final fallbackRes = incoming == null ? ref.watch(reservationProvider(c.reservationId)).valueOrNull : null;
    final guest = incoming ?? fallbackRes;

    return Material(
      color: context.brand.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => context.push('/cleaning/${c.id}'),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.brand.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // 호점 컬러바
              Container(width: 5, constraints: const BoxConstraints(minHeight: 60), color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          // 호점 배지 (색상)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              branch.name,
                              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800),
                            ),
                          ),
                          SizedBox(width: 6),
                          // 실제 날짜
                          Text(
                            dateStr,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.brand.text),
                          ),
                          Spacer(),
                          _statusPill(c, isMine),
                        ],
                      ),
                      SizedBox(height: 6),
                      if (guest != null) ...[
                        Text(
                          '${guest.guestName} · 👤 ${guest.guestCount}인',
                          style: TextStyle(fontSize: 13, color: context.brand.text, fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2),
                        Text(
                          incoming != null ? '신규 입실 게스트' : '체크아웃 게스트',
                          style: TextStyle(
                            fontSize: 10,
                            color: incoming != null ? color : context.brand.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else
                        Text(
                          '게스트 정보 없음',
                          style: TextStyle(fontSize: 12, color: context.brand.muted),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.chevron_right, color: context.brand.dim, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(CleaningModel c, bool isMine) {
    String text;
    Color color;
    bool withCheck = false;
    if (c.isCompleted) {
      text = '완료';
      color = AppColors.ok;
      withCheck = true;
    } else if (c.isUnassigned) {
      text = '?';
      color = const Color(0xFFFACC15);
    } else if (c.status == 'in_progress') {
      text = '작업중';
      color = AppColors.warn;
    } else if (isMine) {
      text = '내 작업';
      color = AppColors.branch1;
    } else {
      text = '배정됨';
      color = AppColors.muted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (withCheck) ...[
            Icon(Icons.check, size: 12, color: color),
            const SizedBox(width: 2),
          ],
          Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// 매니저 홈 — 전체 운영 관점.
/// ① 이번 달 요약(완료/전체/남음·미배정) ② 호점별 현황(가장 가까운 청소 1건씩)
/// ③ 처리 필요 — 미배정 청소 목록(탭하면 상세에서 배정).
class _ManagerHomeView extends ConsumerWidget {
  final List<BranchModel> branches;
  final List<CleaningModel> allCleanings;
  const _ManagerHomeView({required this.branches, required this.allCleanings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservations = ref.watch(upcomingReservationsProvider).valueOrNull ?? const <ReservationModel>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);
    final nextMonthStart = DateTime(now.year, now.month + 1, 1);

    // 이번 달 청소 통계 (scheduledDate가 이번 달)
    final monthCleanings = allCleanings.where((c) {
      final d = c.scheduledDate;
      return !d.isBefore(monthStart) && d.isBefore(nextMonthStart);
    }).toList();
    final monthTotal = monthCleanings.length;
    final monthDone = monthCleanings.where((c) => c.isCompleted).length;
    final monthUnassigned = monthCleanings.where((c) => c.isUnassigned).length;

    // 호점별 가장 가까운(오늘 이후) 청소 1건
    final sortedByDate = [...allCleanings]..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
    final Map<String, CleaningModel?> nearestByBranch = {for (final b in branches) b.id: null};
    for (final c in sortedByDate) {
      final d = DateTime(c.scheduledDate.year, c.scheduledDate.month, c.scheduledDate.day);
      if (d.isBefore(today)) continue;
      if (nearestByBranch.containsKey(c.branchId) && nearestByBranch[c.branchId] == null) {
        nearestByBranch[c.branchId] = c;
      }
    }

    // 처리 필요 — 미배정(오늘 이후) 가까운 순
    final unassigned = sortedByDate.where((c) {
      final d = DateTime(c.scheduledDate.year, c.scheduledDate.month, c.scheduledDate.day);
      return c.isUnassigned && !d.isBefore(today);
    }).toList();

    // 청소일 이후 같은 호점에서 가장 가까운 입실 예약 매칭
    ReservationModel? incomingOf(CleaningModel c) {
      final cd = DateTime(c.scheduledDate.year, c.scheduledDate.month, c.scheduledDate.day);
      ReservationModel? best;
      for (final r in reservations) {
        if (r.branchId != c.branchId) continue;
        final inDay = DateTime(r.checkIn.year, r.checkIn.month, r.checkIn.day);
        if (inDay.isBefore(cd)) continue;
        if (best == null || r.checkIn.isBefore(best.checkIn)) best = r;
      }
      return best;
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ① 이번 달 요약
        _MonthSummaryCard(total: monthTotal, done: monthDone, unassigned: monthUnassigned),
        const SizedBox(height: 22),

        // ② 호점별 현황
        const _SectionTitle('호점별 현황'),
        const SizedBox(height: 10),
        ...branches.map((b) {
          final nearest = nearestByBranch[b.id];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: nearest == null ? _EmptyBranchCard(branch: b) : _TaskCard(cleaning: nearest, branch: b),
          );
        }),
        const SizedBox(height: 22),

        // ③ 처리 필요 — 미배정 청소
        _SectionTitle('처리 필요 — 미배정 ${unassigned.length}건'),
        const SizedBox(height: 10),
        if (unassigned.isEmpty)
          _EmptyAssignmentCard(text: '처리할 미배정 청소가 없습니다')
        else
          ...unassigned.take(8).map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CleaningTaskCard(item: _TaskItem(cleaning: c, incoming: incomingOf(c)), branches: branches),
              )),
        if (unassigned.length > 8) ...[
          const SizedBox(height: 2),
          Text(
            '외 ${unassigned.length - 8}건 더 — 일정 탭에서 확인',
            style: TextStyle(fontSize: 11, color: context.brand.dim),
          ),
        ],
      ],
    );
  }
}

/// 매니저 홈 — 이번 달 청소 요약 카드 (진행률 + 전체/완료/남음 + 미배정 칩)
class _MonthSummaryCard extends StatelessWidget {
  final int total;
  final int done;
  final int unassigned;
  const _MonthSummaryCard({required this.total, required this.done, required this.unassigned});

  @override
  Widget build(BuildContext context) {
    final remaining = total - done;
    final progress = total == 0 ? 0.0 : done / total;
    final monthLabel = DateFormat('M월', 'ko').format(DateTime.now());
    final hasUnassigned = unassigned > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.brand.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('$monthLabel 청소 현황', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (hasUnassigned ? AppColors.warn : AppColors.ok).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  hasUnassigned ? '미배정 $unassigned건' : '미배정 없음',
                  style: TextStyle(
                    color: hasUnassigned ? AppColors.warn : AppColors.ok,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: context.brand.line,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.ok),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat(context, '$total', '전체', AppColors.branch1),
              _stat(context, '$done', '완료', AppColors.ok),
              _stat(context, '$remaining', '남음', remaining > 0 ? AppColors.warn : context.brand.dim),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String num, String label, Color color) => Expanded(
        child: Column(
          children: [
            Text(num, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: context.brand.muted, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: context.brand.muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// 미배정 청소 카운트 배너 — 클릭 시 캘린더로 이동
class _UnassignedBanner extends ConsumerWidget {
  const _UnassignedBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countAsync = ref.watch(unassignedYearCountProvider);
    final count = countAsync.valueOrNull ?? 0;
    final hasAny = count > 0;
    final color = hasAny ? AppColors.warn : AppColors.ok;

    return Material(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => context.push('/calendar'),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  hasAny ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  color: color, size: 22,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '미배정 청소',
                      style: TextStyle(color: context.brand.muted, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          countAsync.isLoading ? '…' : '$count',
                          style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w900),
                        ),
                        SizedBox(width: 4),
                        Text(
                          '건 (1년 이내)',
                          style: TextStyle(color: context.brand.text, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: color, size: 22),
            ],
          ),
        ),
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
        SizedBox(width: 8),
        _statBox(done.toString(), '완료', AppColors.ok, Icons.check_circle_outline),
        SizedBox(width: 8),
        _statBox(remaining.toString(), '남음', remaining > 0 ? AppColors.warn : context.brand.dim, Icons.pending_outlined),
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
              SizedBox(height: 6),
              Text(num, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
              SizedBox(height: 2),
              Text(label, style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w500)),
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

    // 청소 후 입실하는 "다음 게스트" 표시 (체크아웃하는 이전 게스트가 아님).
    // 같은 호점에서 청소 예정일(=이전 게스트 체크아웃일) 이후 가장 가까운 입실 예약을 매칭.
    final reservations = ref.watch(upcomingReservationsProvider).valueOrNull ?? const <ReservationModel>[];
    bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    final cleanDay = DateTime(cleaning.scheduledDate.year, cleaning.scheduledDate.month, cleaning.scheduledDate.day);
    ReservationModel? incoming;
    for (final r in reservations) {
      if (r.branchId != cleaning.branchId) continue;
      final inDay = DateTime(r.checkIn.year, r.checkIn.month, r.checkIn.day);
      if (inDay.isBefore(cleanDay)) continue; // 청소일 이전 입실(이전 게스트 등) 제외
      if (incoming == null || r.checkIn.isBefore(incoming.checkIn)) incoming = r;
    }
    // 라이브 매칭 실패 시 완료 청소에 저장된 다음 게스트 스냅샷 사용
    String? nextGuestName = incoming?.guestName;
    int? nextGuestCount = incoming?.guestCount;
    DateTime? nextCheckIn = incoming?.checkIn;
    if (nextGuestName == null && cleaning.nextGuestSnapshot != null) {
      final s = cleaning.nextGuestSnapshot!;
      nextGuestName = s['guestName'] as String?;
      nextGuestCount = (s['guestCount'] as num?)?.toInt();
      // 스냅샷에 저장된 다음 게스트 체크인 날짜도 사용 (없을 수 있음)
      final ci = s['checkIn'];
      if (ci is Timestamp) nextCheckIn = ci.toDate();
    }
    final bool sameDayArrival = nextCheckIn != null && sameDay(nextCheckIn, cleaning.scheduledDate);

    return Material(
      color: context.brand.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => context.push('/cleaning/${cleaning.id}'),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.brand.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // 좌측 호점 컬러바 (고정 width, 자동 height)
              Container(
                width: 4,
                constraints: const BoxConstraints(minHeight: 50),
                color: branchColor,
              ),
              SizedBox(width: 12),
                // 호점 정보
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          children: [
                            Text(branch.name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: context.brand.text)),
                            SizedBox(width: 8),
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
                        SizedBox(height: 4),
                        if (nextGuestName != null && nextGuestName.isNotEmpty) ...[
                          Text(
                            '${nextGuestName}님 · 👤 ${nextGuestCount ?? 0}인',
                            style: TextStyle(fontSize: 13, color: context.brand.text, fontWeight: FontWeight.w600),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: 1),
                          Text(
                            sameDayArrival
                                ? '신규 입실 게스트 (당일)'
                                : nextCheckIn != null
                                    ? '다음 입실 ${DateFormat('M/d (E)', 'ko').format(nextCheckIn)}'
                                    : '다음 입실 예정',
                            style: TextStyle(fontSize: 10, color: branchColor, fontWeight: FontWeight.w600),
                          ),
                        ] else
                          Text(
                            '입실 예정 게스트 없음 · 체크아웃 ${DateFormat('M/d (E)', 'ko').format(cleaning.scheduledDate)}',
                            style: TextStyle(fontSize: 13, color: context.brand.muted, fontWeight: FontWeight.w500),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
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
                Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Icon(Icons.chevron_right, color: context.brand.dim, size: 18),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(CleaningModel c, bool isMine) {
    if (c.isCompleted) return _pillWithIcon(Icons.check, '완료', AppColors.ok);
    if (c.isUnassigned) return _pill('?', const Color(0xFFFACC15));
    if (isMine) return _pill('내 작업', AppColors.branch1);
    return _pill('진행중', AppColors.muted);
  }

  Widget _pillWithIcon(IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 2),
            Text(
              text,
              style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );

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
        color: context.brand.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.brand.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          // 좌측 호점 컬러바
          Container(
            width: 4,
            constraints: const BoxConstraints(minHeight: 50),
            color: branchColor.withOpacity(0.5),
          ),
          SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      branch.name,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: context.brand.text),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '다가오는 청소 없음',
                      style: TextStyle(fontSize: 13, color: context.brand.dim, fontWeight: FontWeight.w500),
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
                    color: context.brand.dim.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '−',
                    style: TextStyle(color: context.brand.dim, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
