import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';
import '../cleaning_detail/cleaning_detail_page.dart' show reservationProvider;
import '../notifications/notifications_page.dart' show unreadNotificationCountProvider;
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
                  // 알림 버튼 (모든 사용자) + 미읽 뱃지
                  _NotificationButton(),
                ],
              ),
              const SizedBox(height: 18),

              // 미배정 청소 배너 (연간)
              const _UnassignedBanner(),
              const SizedBox(height: 18),

              // 매니저: 호점별 / 실장·청소원: 타임라인
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
                    // 매니저·실장·청소원 모두 — 호점별 가장 가까운 청소 1건씩 표시.
                    // (자기 작업이면 _TaskCard가 '내 작업' 배지로 구분해서 보여줌)
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _SectionTitle('다가오는 청소'),
                        const SizedBox(height: 10),
                        Expanded(
                          child: _BranchList(
                            branches: loadedBranches,
                            cleanings: cleaningsAsync.valueOrNull ?? const <CleaningModel>[],
                            myUid: user?.uid,
                          ),
                        ),
                      ],
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

/// 실장/청소원 전용 — 오늘의 청소 / 다가오는 청소(7일 이내)
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
        const SizedBox(height: 10),
        if (todays.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: const Center(
              child: Text('오늘 청소가 없습니다', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ),
          )
        else
          ...todays.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CleaningTaskCard(item: t, branches: branches),
              )),
        const SizedBox(height: 22),
        const _SectionTitle('다가오는 청소'),
        const SizedBox(height: 10),
        if (upcoming.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.line),
            ),
            child: const Center(
              child: Text('7일 이내 예정된 청소가 없습니다', style: TextStyle(color: AppColors.muted, fontSize: 13)),
            ),
          )
        else
          ...upcoming.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CleaningTaskCard(item: t, branches: branches),
              )),
        const SizedBox(height: 20),
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
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => context.push('/cleaning/${c.id}'),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.line),
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
                          const SizedBox(width: 6),
                          // 실제 날짜
                          Text(
                            dateStr,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.text),
                          ),
                          const Spacer(),
                          _statusPill(c, isMine),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (guest != null) ...[
                        Text(
                          '${guest.guestName} · 👤 ${guest.guestCount}인',
                          style: const TextStyle(fontSize: 13, color: AppColors.text, fontWeight: FontWeight.w600),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          incoming != null ? '신규 입실 게스트' : '체크아웃 게스트',
                          style: TextStyle(
                            fontSize: 10,
                            color: incoming != null ? color : AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ] else
                        Text(
                          '게스트 정보 없음',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                    ],
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.chevron_right, color: AppColors.dim, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusPill(CleaningModel c, bool isMine) {
    String text; Color color;
    if (c.isCompleted) { text = '✓ 완료'; color = AppColors.ok; }
    else if (c.isUnassigned) { text = '미지정'; color = AppColors.warn; }
    else if (isMine) { text = '내 작업'; color = AppColors.branch1; }
    else { text = '배정됨'; color = AppColors.muted; }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
    );
  }
}

/// 호점 목록 — 내가 담당(claim)한 청소만 호점별로 가장 가까운 1건씩 표시
class _BranchList extends StatelessWidget {
  final List<BranchModel> branches;
  final List<CleaningModel> cleanings; // 이미 scheduledDate 오름차순 정렬됨
  final String? myUid;
  const _BranchList({required this.branches, required this.cleanings, required this.myUid});

  @override
  Widget build(BuildContext context) {
    // 호점별로 가장 가까운 청소 1건씩 (배정 여부 무관).
    // upcomingCleaningsProvider는 캘린더용으로 과거 7일도 포함하므로
    // 홈 "다가오는 청소"에서는 오늘 이후 청소만 대상으로 한다.
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final Map<String, CleaningModel?> nearestByBranch = {};
    for (final b in branches) {
      nearestByBranch[b.id] = null;
    }
    for (final c in cleanings) {
      final d = DateTime(c.scheduledDate.year, c.scheduledDate.month, c.scheduledDate.day);
      if (d.isBefore(todayStart)) continue;
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

/// 미읽 알림 개수 뱃지가 표시되는 알림 버튼
class _NotificationButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, size: 22),
            onPressed: () => context.push('/notifications'),
            tooltip: '알림',
            color: AppColors.text,
          ),
          if (unread > 0)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.panel, width: 1.5),
                ),
                alignment: Alignment.center,
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
              ),
            ),
        ],
      ),
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '미배정 청소',
                      style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          countAsync.isLoading ? '…' : '$count',
                          style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '건 (1년 이내)',
                          style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
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
    final DateTime? nextCheckIn = incoming?.checkIn;
    if (nextGuestName == null && cleaning.nextGuestSnapshot != null) {
      final s = cleaning.nextGuestSnapshot!;
      nextGuestName = s['guestName'] as String?;
      nextGuestCount = (s['guestCount'] as num?)?.toInt();
    }
    final bool sameDayArrival = nextCheckIn != null && sameDay(nextCheckIn, cleaning.scheduledDate);

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
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // 좌측 호점 컬러바 (고정 width, 자동 height)
              Container(
                width: 4,
                constraints: const BoxConstraints(minHeight: 50),
                color: branchColor,
              ),
              const SizedBox(width: 12),
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
                        if (nextGuestName != null && nextGuestName.isNotEmpty) ...[
                          Text(
                            '${nextGuestName}님 · 👤 ${nextGuestCount ?? 0}인',
                            style: const TextStyle(fontSize: 13, color: AppColors.text, fontWeight: FontWeight.w600),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            sameDayArrival
                                ? '신규 입실 게스트 (당일)'
                                : '다음 입실 ${DateFormat('M/d (E)', 'ko').format(nextCheckIn!)}',
                            style: TextStyle(fontSize: 10, color: branchColor, fontWeight: FontWeight.w600),
                          ),
                        ] else
                          Text(
                            '입실 예정 게스트 없음 · 체크아웃 ${DateFormat('M/d (E)', 'ko').format(cleaning.scheduledDate)}',
                            style: const TextStyle(fontSize: 13, color: AppColors.muted, fontWeight: FontWeight.w500),
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
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          // 좌측 호점 컬러바
          Container(
            width: 4,
            constraints: const BoxConstraints(minHeight: 50),
            color: branchColor.withOpacity(0.5),
          ),
          const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
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
    );
  }
}
