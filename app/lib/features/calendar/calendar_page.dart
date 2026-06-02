import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';
import '../cleaning_detail/cleaning_detail_page.dart' show cleaningProvider;
import '../shared/bottom_nav.dart';

/// ⑤ 캘린더 (Airbnb 스타일 — 셀 그리드 + 별도 overlay 레이어)
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  DateTime _focusedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;
  final _sheetController = DraggableScrollableController();

  static const _minSheetSize = 0.18;
  static const _maxSheetSize = 0.92;
  static const _expandedThreshold = 0.35;

  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _sheetController.addListener(_onSheetChanged);
  }

  void _onSheetChanged() {
    final expanded = _sheetController.size > _expandedThreshold;
    if (expanded != _isExpanded) {
      setState(() => _isExpanded = expanded);
    }
  }

  @override
  void dispose() {
    _sheetController.removeListener(_onSheetChanged);
    _sheetController.dispose();
    super.dispose();
  }

  void _toggleSheet() {
    final isExpanded = _sheetController.size > (_minSheetSize + _maxSheetSize) / 2;
    _sheetController.animateTo(
      isExpanded ? _minSheetSize : _maxSheetSize,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _goPrevMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    });
  }

  void _goNextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    });
  }

  /// 특정 날짜에 머무는 모든 예약 (체크인 <= day <= 체크아웃)
  List<ReservationModel> _reservationsOnDay(List<ReservationModel> all, DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    return all.where((r) {
      final inStart = DateTime(r.checkIn.year, r.checkIn.month, r.checkIn.day);
      final outStart = DateTime(r.checkOut.year, r.checkOut.month, r.checkOut.day);
      return !dayStart.isBefore(inStart) && !dayStart.isAfter(outStart);
    }).toList()
      ..sort((a, b) => a.branchId.compareTo(b.branchId));
  }

  @override
  Widget build(BuildContext context) {
    final reservationsAsync = ref.watch(upcomingReservationsProvider);
    final cleaningsAsync = ref.watch(upcomingCleaningsProvider);
    final branches = ref.watch(branchesProvider).value ?? const <BranchModel>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('일정'),
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: const AppBottomNav(active: BottomTab.calendar),
      body: reservationsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (reservations) {
          final selectedDay = _selectedDay ?? DateTime.now();
          final selectedReservations = _reservationsOnDay(reservations, selectedDay);
          final cleaningsList = cleaningsAsync.valueOrNull ?? const <CleaningModel>[];
          final cleaningByResId = <String, CleaningModel>{
            for (final c in cleaningsList)
              if (c.reservationId.isNotEmpty) c.reservationId: c,
          };

          return Stack(
            children: [
              // 배경: 커스텀 월간 캘린더 (스크롤 가능)
              Column(
                children: [
                  _MonthHeader(
                    month: _focusedMonth,
                    onPrev: _goPrevMonth,
                    onNext: _goNextMonth,
                  ),
                  _BranchLegend(branches: branches),
                  const _WeekdayRow(),
                  Expanded(
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.trackpad,
                        },
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 200), // 시트 영역 여유
                        child: _MonthGrid(
                          month: _focusedMonth,
                          today: DateTime.now(),
                          selectedDay: _selectedDay,
                          reservations: reservations,
                          cleaningByResId: cleaningByResId,
                          onDayTap: (day) => setState(() => _selectedDay = day),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // 바텀 시트
              DraggableScrollableSheet(
                controller: _sheetController,
                initialChildSize: _minSheetSize,
                minChildSize: _minSheetSize,
                maxChildSize: _maxSheetSize,
                snap: true,
                snapSizes: const [_minSheetSize, _maxSheetSize],
                builder: (context, scrollController) {
                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          offset: const Offset(0, -3),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // 시트 상단 전체(핸들 + 날짜 헤더)에서 드래그 가능
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _toggleSheet,
                          onVerticalDragUpdate: (details) {
                            final screenHeight = MediaQuery.of(context).size.height;
                            final delta = -details.delta.dy / screenHeight;
                            final newSize = (_sheetController.size + delta)
                                .clamp(_minSheetSize, _maxSheetSize);
                            _sheetController.jumpTo(newSize);
                          },
                          onVerticalDragEnd: (details) {
                            // 속도 기반: 위로 빠르게 swipe하면 즉시 펼치고, 아래로 빠르게 swipe하면 즉시 접음
                            final velocity = details.primaryVelocity ?? 0;
                            const flingThreshold = 200.0; // px/sec
                            double target;
                            if (velocity < -flingThreshold) {
                              target = _maxSheetSize;
                            } else if (velocity > flingThreshold) {
                              target = _minSheetSize;
                            } else {
                              // 천천히 놓았을 때: min에서 조금만 위로 올려도 펼쳐지도록 임계값 낮춤
                              final threshold = _minSheetSize + (_maxSheetSize - _minSheetSize) * 0.25;
                              target = _sheetController.size > threshold ? _maxSheetSize : _minSheetSize;
                            }
                            _sheetController.animateTo(
                              target,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                            );
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                color: Colors.transparent,
                                child: Center(
                                  child: Container(
                                    width: 40,
                                    height: 4,
                                    decoration: BoxDecoration(
                                      color: AppColors.dim,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                                child: Row(
                                  children: [
                                    Text(
                                      DateFormat('M월 d일 (E)', 'ko').format(selectedDay),
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                    ),
                                    const Spacer(),
                                    if (selectedReservations.isNotEmpty)
                                      Text('${selectedReservations.length}건 숙박',
                                          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: cleaningsAsync.when(
                            loading: () => const SizedBox.shrink(),
                            error: (_, __) => const SizedBox.shrink(),
                            data: (cleanings) => _BottomList(
                              selectedReservations: selectedReservations,
                              allReservations: reservations,
                              cleanings: cleanings,
                              branches: branches,
                              ref: ref,
                              scrollController: scrollController,
                              showUpcoming: _isExpanded,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 월간 헤더
// ═══════════════════════════════════════════════════════════════════

class _MonthHeader extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _MonthHeader({required this.month, required this.onPrev, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left, color: AppColors.text),
            iconSize: 22,
          ),
          Expanded(
            child: Center(
              child: Text(
                DateFormat('yyyy년 M월', 'ko').format(month),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right, color: AppColors.text),
            iconSize: 22,
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 호점 색상 범례
// ═══════════════════════════════════════════════════════════════════

class _BranchLegend extends StatelessWidget {
  final List<BranchModel> branches;
  const _BranchLegend({required this.branches});

  @override
  Widget build(BuildContext context) {
    if (branches.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        children: branches.map((b) {
          final color = AppColors.branchColor(b.id);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10, height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(b.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.muted)),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 요일 헤더
// ═══════════════════════════════════════════════════════════════════

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  static const _labels = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Row(
        children: List.generate(7, (i) {
          final isWeekend = i == 0 || i == 6;
          return Expanded(
            child: Center(
              child: Text(
                _labels[i],
                style: TextStyle(
                  color: isWeekend ? AppColors.danger : AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 월간 그리드 (주별 행)
// ═══════════════════════════════════════════════════════════════════

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final DateTime today;
  final DateTime? selectedDay;
  final List<ReservationModel> reservations;
  final Map<String, CleaningModel> cleaningByResId;
  final ValueChanged<DateTime> onDayTap;
  const _MonthGrid({
    required this.month,
    required this.today,
    required this.selectedDay,
    required this.reservations,
    required this.cleaningByResId,
    required this.onDayTap,
  });

  /// 월간 그리드의 모든 날짜 (주 단위 7개씩 묶음) — 일요일 시작
  List<List<DateTime>> _buildWeeks() {
    final first = DateTime(month.year, month.month, 1);
    // 일요일=7→0 변환. Dart의 weekday: 월=1, 일=7
    final firstSunOffset = first.weekday % 7; // 일요일이면 0, 월=1, ..., 토=6
    final start = first.subtract(Duration(days: firstSunOffset));

    final weeks = <List<DateTime>>[];
    var cursor = start;
    while (true) {
      final week = List.generate(7, (i) => cursor.add(Duration(days: i)));
      // 이 주에 해당 월 날짜가 하나라도 있으면 포함
      final hasMonthDay = week.any((d) => d.month == month.month && d.year == month.year);
      if (hasMonthDay) {
        weeks.add(week);
      }
      cursor = cursor.add(const Duration(days: 7));
      if (!hasMonthDay && weeks.isNotEmpty) break;
      if (weeks.length >= 6) break;
    }
    return weeks;
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _buildWeeks();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: weeks.map((week) => _WeekRow(
          days: week,
          month: month,
          today: today,
          selectedDay: selectedDay,
          reservations: reservations,
          cleaningByResId: cleaningByResId,
          onDayTap: onDayTap,
        )).toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 한 주 — 셀 + Pill overlay
// ═══════════════════════════════════════════════════════════════════

class _WeekRow extends StatelessWidget {
  final List<DateTime> days; // 7
  final DateTime month;
  final DateTime today;
  final DateTime? selectedDay;
  final List<ReservationModel> reservations;
  final Map<String, CleaningModel> cleaningByResId;
  final ValueChanged<DateTime> onDayTap;
  const _WeekRow({
    required this.days,
    required this.month,
    required this.today,
    required this.selectedDay,
    required this.reservations,
    required this.cleaningByResId,
    required this.onDayTap,
  });

  /// 이 주에 표시할 pill 목록 계산 (체크인 셀 중앙 → 체크아웃 셀 중앙)
  /// 같은 날 핸드오버(체크아웃=체크인)는 한 점에서 만나므로 같은 트랙에 배치됨
  DateTime _maxDay(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
  DateTime _minDay(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<_PillLayout> _layoutPills() {
    final weekStart = DateTime(days.first.year, days.first.month, days.first.day);
    final weekEnd = DateTime(days.last.year, days.last.month, days.last.day);

    // 현재 월 경계
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 0); // 월 마지막 날

    // 실제 표시 범위 = 주 ∩ 월
    final visStart = _maxDay(weekStart, monthStart);
    final visEnd = _minDay(weekEnd, monthEnd);

    final visibleRes = <_ResRange>[];
    for (final r in reservations) {
      final inDay = DateTime(r.checkIn.year, r.checkIn.month, r.checkIn.day);
      final outDay = DateTime(r.checkOut.year, r.checkOut.month, r.checkOut.day);

      // 예약이 표시 범위와 겹치지 않으면 스킵
      if (outDay.isBefore(visStart) || inDay.isAfter(visEnd)) continue;

      // 월+주 경계로 클리핑
      final clampedIn = _maxDay(inDay, visStart);
      final clampedOut = _minDay(outDay, visEnd);

      final isStartCap = _sameDay(clampedIn, inDay);
      final isEndCap = _sameDay(clampedOut, outDay);
      final isMonthClippedStart = !isStartCap && inDay.isBefore(monthStart);
      final isMonthClippedEnd = !isEndCap && outDay.isAfter(monthEnd);
      final startCol = clampedIn.difference(weekStart).inDays;
      final endCol = clampedOut.difference(weekStart).inDays;
      visibleRes.add(_ResRange(
        reservation: r,
        startCol: startCol,
        endCol: endCol,
        isStartCap: isStartCap,
        isEndCap: isEndCap,
        isMonthClippedStart: isMonthClippedStart,
        isMonthClippedEnd: isMonthClippedEnd,
      ));
    }

    // 호점별 고정 트랙: branch1 → 0, branch2 → 1, branch3 → 2
    int trackOf(String branchId) {
      switch (branchId) {
        case 'branch1': return 0;
        case 'branch2': return 1;
        case 'branch3': return 2;
        default: return 3;
      }
    }

    final result = <_PillLayout>[];
    for (final res in visibleRes) {
      result.add(_PillLayout(range: res, track: trackOf(res.reservation.branchId)));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final pills = _layoutPills();
    // 트랙 수에 따라 row 높이 동적 (정사각에 가깝게)
    final trackCount = pills.isEmpty ? 0 : pills.map((p) => p.track).fold<int>(0, (m, v) => v > m ? v : m) + 1;
    const rowHeightBase = 90.0;
    const pillH = 26.0;
    const pillVGap = 5.0;
    // pill을 가운데보다 살짝 위로
    final pillBottomBase = rowHeightBase / 2 - pillH / 2 + 6;
    final rowHeight = rowHeightBase + (trackCount > 1 ? (trackCount - 1) * (pillH + pillVGap) : 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 6.0;
        final cellW = (constraints.maxWidth - gap * 6) / 7;

        return SizedBox(
          height: rowHeight + 6, // 여유
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Layer 1: 셀 카드 7개
              Row(
                children: List.generate(7, (i) {
                  final day = days[i];
                  return Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : gap),
                    child: SizedBox(
                      width: cellW,
                      child: _DayCard(
                        day: day,
                        month: month,
                        today: today,
                        selectedDay: selectedDay,
                        height: rowHeight,
                        onTap: () => onDayTap(day),
                      ),
                    ),
                  );
                }),
              ),
              // Layer 2: Pill bars (절대 배치, 셀 중앙→중앙)
              ...pills.map((p) {
                final r = p.range;
                // 체크인 셀 중앙 = startCol * (cellW+gap) + cellW/2
                // 체크아웃 셀 중앙 = endCol * (cellW+gap) + cellW/2
                // cap 없으면 셀 끝까지 (좌측: 0, 우측: 전체 폭)
                final left = (r.isStartCap || r.isMonthClippedStart)
                    ? r.startCol * (cellW + gap) + cellW / 2
                    : 0.0;
                final right = (r.isEndCap || r.isMonthClippedEnd)
                    ? r.endCol * (cellW + gap) + cellW / 2
                    : 7 * (cellW + gap) - gap;
                final width = right - left;
                // 호점 트랙은 위에서부터 (track 0 = 맨 위)
                final invTrack = (trackCount - 1) - p.track;
                final bottom = pillBottomBase + invTrack * (pillH + pillVGap);
                // 청소 데이터가 없거나(아직 미생성/로드 전) 미배정이면 '!' 배지.
                // null을 false로 떨어뜨려 초록 체크가 잘못 뜨던 버그 방지.
                final cleaning = cleaningByResId[r.reservation.id];
                final isUnassigned = cleaning == null || cleaning.isUnassigned;
                return Positioned(
                  left: left,
                  width: width,
                  bottom: bottom,
                  height: pillH,
                  child: IgnorePointer(
                    child: _Pill(
                      reservation: r.reservation,
                      isStartCap: r.isStartCap,
                      isEndCap: r.isEndCap,
                      isUnassigned: isUnassigned,
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

class _ResRange {
  final ReservationModel reservation;
  final int startCol; // 0~6
  final int endCol;   // 0~6
  final bool isStartCap; // 좌측 둥글게 (원래 체크인이 보임)
  final bool isEndCap;   // 우측 둥글게 (원래 체크아웃이 보임)
  final bool isMonthClippedStart; // 월 경계에서 잘림 (셀 중앙 위치)
  final bool isMonthClippedEnd;   // 월 경계에서 잘림 (셀 중앙 위치)
  _ResRange({
    required this.reservation,
    required this.startCol,
    required this.endCol,
    required this.isStartCap,
    required this.isEndCap,
    this.isMonthClippedStart = false,
    this.isMonthClippedEnd = false,
  });
}

class _PillLayout {
  final _ResRange range;
  final int track;
  _PillLayout({required this.range, required this.track});
}

// ═══════════════════════════════════════════════════════════════════
// 셀 카드
// ═══════════════════════════════════════════════════════════════════

class _DayCard extends StatelessWidget {
  final DateTime day;
  final DateTime month;
  final DateTime today;
  final DateTime? selectedDay;
  final double height;
  final VoidCallback onTap;
  const _DayCard({
    required this.day,
    required this.month,
    required this.today,
    required this.selectedDay,
    required this.height,
    required this.onTap,
  });

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final isThisMonth = day.month == month.month && day.year == month.year;

    // 이번 달이 아닌 날짜는 빈 셀로 표시
    if (!isThisMonth) {
      return SizedBox(height: height + 6);
    }

    final isToday = _sameDay(day, today);
    final isSelected = selectedDay != null && _sameDay(day, selectedDay!);
    final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;

    Color textColor;
    if (isToday || isSelected) {
      textColor = AppColors.branch1;
    } else if (isWeekend) {
      textColor = AppColors.danger;
    } else {
      textColor = AppColors.text;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.branch1.withOpacity(0.06) : AppColors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: (isSelected || isToday) ? AppColors.branch1 : const Color(0xFFEBEBEB),
            width: (isSelected || isToday) ? 1.2 : 0.8,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Align(
            alignment: Alignment.topRight,
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: (isToday || isSelected) ? FontWeight.w800 : FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Pill (overlay bar)
// ═══════════════════════════════════════════════════════════════════

class _Pill extends StatelessWidget {
  final ReservationModel reservation;
  final bool isStartCap;
  final bool isEndCap;
  final bool isUnassigned;
  const _Pill({
    required this.reservation,
    required this.isStartCap,
    required this.isEndCap,
    required this.isUnassigned,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.branchColor(reservation.branchId);
    final initial = reservation.guestName.isNotEmpty ? reservation.guestName[0] : '?';

    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(isStartCap ? 11 : 0),
        bottomLeft: Radius.circular(isStartCap ? 11 : 0),
        topRight: Radius.circular(isEndCap ? 11 : 0),
        bottomRight: Radius.circular(isEndCap ? 11 : 0),
      ),
      child: Container(
        color: color,
        padding: EdgeInsets.only(
          left: isStartCap ? 3 : 0,
          right: isEndCap ? 8 : 0,
        ),
        alignment: Alignment.centerLeft,
        child: isStartCap
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: isUnassigned ? AppColors.warn : AppColors.ok,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    alignment: Alignment.center,
                    child: isUnassigned
                        ? const Text('!', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w900, height: 1.0))
                        : const Icon(Icons.check, size: 13, color: Colors.white),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      '${reservation.guestName}(${reservation.guestCount}명)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 바텀 시트 리스트 (기존 유지)
// ═══════════════════════════════════════════════════════════════════

class _BottomList extends StatelessWidget {
  final List<ReservationModel> selectedReservations;
  final List<ReservationModel> allReservations;
  final List<CleaningModel> cleanings;
  final List<BranchModel> branches;
  final WidgetRef ref;
  final ScrollController? scrollController;
  final bool showUpcoming;
  const _BottomList({
    required this.selectedReservations,
    required this.allReservations,
    required this.cleanings,
    required this.branches,
    required this.ref,
    this.scrollController,
    this.showUpcoming = false,
  });

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 80),
        children: [
          if (selectedReservations.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('이 날 숙박 예약이 없습니다', style: TextStyle(color: AppColors.muted, fontSize: 12)),
              ),
            )
          else
            ...selectedReservations.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _ReservationCard(reservation: r, branches: branches),
                )),

          if (showUpcoming) ...[
            const SizedBox(height: 14),
            const Text(
              '다가오는 청소',
              style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            ..._buildUpcomingReservationCards(),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildUpcomingReservationCards() {
    final selectedIds = selectedReservations.map((r) => r.id).toSet();
    final shown = <String>{};
    final cards = <Widget>[];

    for (final c in cleanings) {
      if (c.reservationId.isEmpty) continue;
      if (selectedIds.contains(c.reservationId)) continue;
      if (shown.contains(c.reservationId)) continue;
      shown.add(c.reservationId);

      final res = allReservations.where((r) => r.id == c.reservationId).toList();
      if (res.isEmpty) continue;

      cards.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _ReservationCard(reservation: res.first, branches: branches),
      ));
      if (cards.length >= 10) break;
    }

    if (cards.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text('다가오는 청소가 없습니다', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
        )
      ];
    }
    return cards;
  }
}

class _ReservationCard extends ConsumerWidget {
  final ReservationModel reservation;
  final List<BranchModel> branches;
  const _ReservationCard({required this.reservation, required this.branches});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = branches.firstWhere(
      (b) => b.id == reservation.branchId,
      orElse: () => BranchModel(id: reservation.branchId, name: reservation.branchId, rooms: 0, maxOccupancy: 0, color: '#64748B', iCalSourceUrl: '', active: true),
    );
    final branchColor = AppColors.branchColor(reservation.branchId);
    final fmt = DateFormat('M/d (E)', 'ko');

    final cleaningAsync = ref.watch(cleaningProvider(reservation.id));
    final cleaning = cleaningAsync.valueOrNull;
    final user = ref.watch(currentUserProvider).valueOrNull;
    final isMine = cleaning != null && user != null && cleaning.assigneeUid == user.uid;
    final canClaim = cleaning != null && cleaning.isUnassigned;

    Widget? rightAction;
    if (cleaning != null) {
      if (canClaim) {
        rightAction = SizedBox(
          height: 36,
          child: FilledButton.icon(
            onPressed: () => _claim(context, ref, cleaning.id),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('내가 할게요'),
          ),
        );
      } else if (isMine) {
        rightAction = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.branch1.withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text('내 작업', style: TextStyle(color: AppColors.branch1, fontSize: 10, fontWeight: FontWeight.w700)),
        );
      } else if (cleaning.isCompleted) {
        rightAction = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.ok.withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text('✓ 완료', style: TextStyle(color: AppColors.ok, fontSize: 10, fontWeight: FontWeight.w700)),
        );
      } else if (cleaning.assigneeUid != null) {
        rightAction = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.muted.withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text('배정됨', style: TextStyle(color: AppColors.muted, fontSize: 10, fontWeight: FontWeight.w700)),
        );
      }
    }

    return Material(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: cleaning == null ? null : () => context.push('/cleaning/${cleaning.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
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
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${reservation.guestName}(${reservation.guestCount}명)',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${fmt.format(reservation.checkIn)} → ${fmt.format(reservation.checkOut)}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    if (cleaning != null && cleaning.assigneeName != null && cleaning.assigneeName!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            Icon(Icons.person, size: 12, color: isMine ? AppColors.branch1 : AppColors.muted),
                            const SizedBox(width: 3),
                            Text(
                              cleaning.assigneeName!,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isMine ? AppColors.branch1 : AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (rightAction != null) ...[
                const SizedBox(width: 10),
                rightAction,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _claim(BuildContext context, WidgetRef ref, String cleaningId) async {
    try {
      await ref.read(functionsServiceProvider).claimCleaning(cleaningId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('청소를 담당하기로 했어요'), backgroundColor: AppColors.ok),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('배정 실패: $e')));
      }
    }
  }
}
