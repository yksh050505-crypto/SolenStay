import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/holidays.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';
import '../cleaning_detail/cleaning_detail_page.dart' show cleaningProvider;
import '../shared/bottom_nav.dart';
import '../shared/notification_bell.dart';

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
        title: Text('일정'),
        automaticallyImplyLeading: false,
        actions: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: NotificationBellButton(),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(active: BottomTab.calendar),
      body: reservationsAsync.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (reservations) {
          final selectedDay = _selectedDay ?? DateTime.now();
          final selectedHoliday = holidayName(selectedDay);
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
                      color: context.brand.bg,
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
                                      color: context.brand.dim,
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
                                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                    ),
                                    if (selectedHoliday != null) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.danger.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          selectedHoliday,
                                          style: const TextStyle(
                                              color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ],
                                    Spacer(),
                                    if (selectedReservations.isNotEmpty)
                                      Text('${selectedReservations.length}건 숙박',
                                          style: TextStyle(color: context.brand.muted, fontSize: 12)),
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
            icon: Icon(Icons.chevron_left, color: context.brand.text),
            iconSize: 22,
          ),
          Expanded(
            child: Center(
              child: Text(
                DateFormat('yyyy년 M월', 'ko').format(month),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: Icon(Icons.chevron_right, color: context.brand.text),
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
              SizedBox(width: 4),
              Text(b.name, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.brand.muted)),
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
                  color: isWeekend ? AppColors.danger : context.brand.muted,
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          // _WeekRow와 동일한 셀 폭 계산 → 칸별 글자 reflow 미리 산출
          final compact = constraints.maxWidth < 380;
          final gap = compact ? 4.0 : 6.0;
          final cellW = (constraints.maxWidth - gap * 6) / 7;
          final reflowLabels = _computeReflowLabels(
            reservations: reservations,
            weeks: weeks,
            month: month,
            cellW: cellW,
            gap: gap,
            scaler: MediaQuery.textScalerOf(context),
            today: today,
            cleaningByResId: cleaningByResId,
          );
          return Column(
            children: weeks.map((week) => _WeekRow(
              days: week,
              month: month,
              today: today,
              selectedDay: selectedDay,
              reservations: reservations,
              cleaningByResId: cleaningByResId,
              onDayTap: onDayTap,
              reflowLabels: reflowLabels,
            )).toList(),
          );
        },
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
  /// key: "${reservationId}|${weekStartIso}" → 이 주 구간에 표시할 라벨 글자 (reflow)
  final Map<String, String> reflowLabels;
  const _WeekRow({
    required this.days,
    required this.month,
    required this.today,
    required this.selectedDay,
    required this.reservations,
    required this.cleaningByResId,
    required this.onDayTap,
    required this.reflowLabels,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // 좁은 화면(아이폰 미니/SE 등) 자동 compact 모드 — pill 높이/여백 축소
        final compact = constraints.maxWidth < 380;
        final rowHeightBase = compact ? 60.0 : 74.0;
        final pillH = compact ? 20.0 : 26.0;
        const pillVGap = 0.0;
        final pillBottomBase = compact ? 7.0 : 10.0;
        final rowHeight = rowHeightBase + (trackCount > 1 ? (trackCount - 1) * (pillH + pillVGap) : 0);
        final gap = compact ? 4.0 : 6.0;
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
                // 실제 체크인/아웃(cap)만 셀 "중앙"에서 시작/끝(핸드오버 표현).
                // 그 외엔 주 경계든 월 경계든 동일하게 "보이는 셀의 가장자리"까지 꽉 채워
                // 다음 주/다음 달로 이어짐을 표시 (이전엔 월 경계가 중앙에서 잘리던 버그).
                final left = r.isStartCap
                    ? r.startCol * (cellW + gap) + cellW / 2
                    : r.startCol * (cellW + gap);
                final right = r.isEndCap
                    ? r.endCol * (cellW + gap) + cellW / 2
                    : r.endCol * (cellW + gap) + cellW;
                final width = right - left;
                // 호점 트랙은 위에서부터 (track 0 = 맨 위)
                final invTrack = (trackCount - 1) - p.track;
                final bottom = pillBottomBase + invTrack * (pillH + pillVGap);
                // 청소 데이터가 없거나(아직 미생성/로드 전) 미배정이면 '!' 배지.
                // null을 false로 떨어뜨려 초록 체크가 잘못 뜨던 버그 방지.
                final cleaning = cleaningByResId[r.reservation.id];
                final isUnassigned = cleaning == null || cleaning.isUnassigned;
                final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
                final coDay = DateTime(r.reservation.checkOut.year, r.reservation.checkOut.month, r.reservation.checkOut.day);
                final isPast = coDay.isBefore(today);
                // 한 주의 시작 셀(일요일, col 0)에 위치한 pill — 이전 주에서 이어진 경우라도
                // 텍스트를 다시 표시해서 끝나는 셀에서 잘리는 경우를 보완.
                final isWeekStart = r.startCol == 0 && !r.isStartCap;
                final weekStart = DateTime(days.first.year, days.first.month, days.first.day);
                final segLabel = reflowLabels['${r.reservation.id}|${weekStart.toIso8601String()}'] ?? '';
                return Positioned(
                  left: left,
                  width: width,
                  bottom: bottom,
                  height: pillH,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: isPast ? 0.5 : 1.0,
                      child: _Pill(
                        reservation: r.reservation,
                        isStartCap: r.isStartCap,
                        isEndCap: r.isEndCap,
                        isUnassigned: isUnassigned,
                        isWeekStart: isWeekStart,
                        labelText: segLabel,
                        showChip: r.isStartCap,
                      ),
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
    final holiday = holidayName(day);

    Color textColor;
    if (isToday || isSelected) {
      textColor = AppColors.branch1;
    } else if (isWeekend || holiday != null) {
      textColor = AppColors.danger;
    } else {
      textColor = context.brand.text;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.branch1.withOpacity(0.06) : context.brand.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: (isSelected || isToday) ? AppColors.branch1 : context.brand.line,
            width: (isSelected || isToday) ? 1.2 : 0.8,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (holiday != null)
                Expanded(
                  child: Text(
                    holiday,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger,
                      height: 1.15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    softWrap: false,
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: 2),
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: (isToday || isSelected) ? FontWeight.w800 : FontWeight.w600,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Pill 라벨 reflow — 긴 이름이 한 칸에서 잘리면 이어지는 칸으로 "이어서" 표시
// ═══════════════════════════════════════════════════════════════════

const TextStyle _pillNameStyle = TextStyle(
    fontSize: 12, color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: -0.2);
const TextStyle _pillChipStyle = TextStyle(
    fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: -0.3, height: 1.1);

double _measureTextWidth(String text, TextStyle style, TextScaler scaler) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: ui.TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  return tp.width;
}

/// text[from:] 중 maxWidth 안에 들어가는 최대 글자 수
int _charsThatFit(String text, int from, double maxWidth, TextScaler scaler) {
  if (from >= text.length || maxWidth <= 0) return 0;
  int lo = 0, hi = text.length - from, best = 0;
  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    final w = _measureTextWidth(text.substring(from, from + mid), _pillNameStyle, scaler);
    if (w <= maxWidth) {
      best = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return best;
}

/// 각 예약 라벨을 주(week) 구간별로 잘라 "이어 흐르게" 한 맵.
/// key: "${reservationId}|${weekStartIso}" → 그 구간에 표시할 글자(앞 구간에서 이어짐).
Map<String, String> _computeReflowLabels({
  required List<ReservationModel> reservations,
  required List<List<DateTime>> weeks,
  required DateTime month,
  required double cellW,
  required double gap,
  required TextScaler scaler,
  required DateTime today,
  required Map<String, CleaningModel> cleaningByResId,
}) {
  DateTime d0(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime maxD(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
  DateTime minD(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  bool same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  final monthStart = DateTime(month.year, month.month, 1);
  final monthEnd = DateTime(month.year, month.month + 1, 0);
  final out = <String, String>{};

  for (final r in reservations) {
    final inDay = d0(r.checkIn);
    final outDay = d0(r.checkOut);
    final name = '${r.guestName}(${r.guestCount}명)';
    final cleaning = cleaningByResId[r.id];
    final isUnassigned = cleaning == null || cleaning.isUnassigned;
    int offset = 0;
    for (final week in weeks) {
      final weekStart = d0(week.first);
      final weekEnd = d0(week.last);
      final visStart = maxD(weekStart, monthStart);
      final visEnd = minD(weekEnd, monthEnd);
      if (outDay.isBefore(visStart) || inDay.isAfter(visEnd)) continue;
      final clampedIn = maxD(inDay, visStart);
      final clampedOut = minD(outDay, visEnd);
      final isStartCap = same(clampedIn, inDay);
      final isEndCap = same(clampedOut, outDay);
      final startCol = clampedIn.difference(weekStart).inDays;
      final endCol = clampedOut.difference(weekStart).inDays;
      final left = isStartCap ? startCol * (cellW + gap) + cellW / 2 : startCol * (cellW + gap);
      final right = isEndCap ? endCol * (cellW + gap) + cellW / 2 : endCol * (cellW + gap) + cellW;
      final segW = right - left;
      // 시작 구간(호점 칩 표시)에서는 칩(+미배정 ?) 폭만큼 이름 공간이 줄어듦
      double chipW = 0;
      if (isStartCap) {
        chipW = _measureTextWidth(AppColors.branchShortLabel(r.branchId), _pillChipStyle, scaler) + 8 + 4;
        if (isUnassigned) {
          chipW += _measureTextWidth('?',
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: -0.5), scaler) +
              4;
        }
      }
      final padLR = 6 + (isEndCap ? 8.0 : 4.0);
      final avail = segW - padLR - chipW;
      final key = '${r.id}|${weekStart.toIso8601String()}';
      if (offset >= name.length) {
        out[key] = '';
        continue;
      }
      final count = _charsThatFit(name, offset, avail, scaler);
      out[key] = name.substring(offset, offset + count);
      offset += count;
    }
  }
  return out;
}

// ═══════════════════════════════════════════════════════════════════
// Pill (overlay bar)
// ═══════════════════════════════════════════════════════════════════

class _Pill extends StatelessWidget {
  final ReservationModel reservation;
  final bool isStartCap;
  final bool isEndCap;
  final bool isUnassigned;
  /// 한 주의 시작 셀(일요일)에 위치한 pill이면 true.
  /// isStartCap이 false라도 (이전 주에서 이어진 pill) 다음 주 첫 셀에 텍스트를 다시 표시.
  final bool isWeekStart;
  /// 이 구간에 표시할 라벨 글자(앞 구간에서 잘린 다음 글자부터 이어짐). 빈 문자열이면 글자 없음.
  final String labelText;
  /// 호점 칩(+미배정 ?)을 표시할지 — 실제 체크인 구간에서만 true.
  final bool showChip;
  const _Pill({
    required this.reservation,
    required this.isStartCap,
    required this.isEndCap,
    required this.isUnassigned,
    this.isWeekStart = false,
    this.labelText = '',
    this.showChip = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppColors.branchColor(reservation.branchId);
    // pill은 항상 솔리드. 미배정 여부는 좌측 노란 ? 마커로만 표현.
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isStartCap ? 11 : 0),
      bottomLeft: Radius.circular(isStartCap ? 11 : 0),
      topRight: Radius.circular(isEndCap ? 11 : 0),
      bottomRight: Radius.circular(isEndCap ? 11 : 0),
    );
    final borderColor = Colors.black.withOpacity(0.22);
    final borderSide = BorderSide(color: borderColor, width: 1);
    // 입체감: 그라데이션(위 밝게·아래 어둡게) + 살짝 뜬 그림자.
    // 주의: 테두리는 반드시 "균일 색"이어야 함 (둥근 모서리+비균일 테두리는 paint 예외 → 글자 사라짐).
    final topColor = Color.lerp(color, Colors.white, 0.18)!;
    final bottomColor = Color.lerp(color, Colors.black, 0.13)!;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, color, bottomColor],
          stops: const [0.0, 0.5, 1.0],
        ),
        borderRadius: radius,
        border: Border(
          top: borderSide,
          bottom: borderSide,
          left: isStartCap ? borderSide : BorderSide.none,
          right: isEndCap ? borderSide : BorderSide.none,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 2.5,
            offset: const Offset(0, 1.4),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 6,
        right: isEndCap ? 8 : 4,
      ),
      alignment: Alignment.centerLeft,
      // 호점 칩은 실제 체크인 구간에서만, 이름 글자는 reflow로 이어지는 칸마다 "잘린 다음 글자부터" 표시
      child: (showChip || labelText.isNotEmpty)
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showChip) ...[
                  // 호점 라벨 (1호/2호/3호)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      AppColors.branchShortLabel(reservation.branchId),
                      style: TextStyle(
                        fontSize: 9,
                        color: color,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (isUnassigned) ...[
                    const Text(
                      '?',
                      style: TextStyle(
                        fontSize: 15,
                        color: Color(0xFFFACC15), // 노란색 (yellow-400)
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ],
                if (labelText.isNotEmpty)
                  Flexible(
                    child: Text(
                      labelText,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        shadows: [
                          Shadow(color: Color(0x66000000), blurRadius: 1.5, offset: Offset(0, 0.5)),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                    ),
                  ),
              ],
            )
          : null,
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
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('이 날 숙박 예약이 없습니다', style: TextStyle(color: context.brand.muted, fontSize: 12)),
              ),
            )
          else
            ...selectedReservations.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _ReservationCard(reservation: r, branches: branches),
                )),

          if (showUpcoming) ...[
            SizedBox(height: 14),
            Text(
              '다가오는 청소',
              style: TextStyle(color: context.brand.muted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5),
            ),
            SizedBox(height: 8),
            ..._buildUpcomingReservationCards(),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildUpcomingReservationCards() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedIds = selectedReservations.map((r) => r.id).toSet();
    final shown = <String>{};
    final cards = <Widget>[];

    for (final c in cleanings) {
      if (c.reservationId.isEmpty) continue;
      if (selectedIds.contains(c.reservationId)) continue;
      // "다가오는 청소" 목록은 미래만 — 과거 청소는 데이터 윈도우 확장으로 들어오지만 제외
      final cDay = DateTime(c.scheduledDate.year, c.scheduledDate.month, c.scheduledDate.day);
      if (cDay.isBefore(today)) continue;
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
        Padding(
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
      if (cleaning.isCompleted) {
        // 완료된 청소는 본인 작업 여부 무관 — 항상 "✓ 완료"
        rightAction = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.ok.withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.check, size: 13, color: AppColors.ok),
              SizedBox(width: 3),
              Text('완료', style: TextStyle(color: AppColors.ok, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
        );
      } else if (canClaim) {
        rightAction = SizedBox(
          height: 36,
          child: FilledButton.icon(
            onPressed: () => _claim(context, ref, cleaning.id),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              textStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: Icon(Icons.check, size: 16),
            label: Text('내가 할게요'),
          ),
        );
      } else if (isMine) {
        rightAction = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.branch1.withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('내 작업', style: TextStyle(color: AppColors.branch1, fontSize: 11, fontWeight: FontWeight.w700)),
        );
      } else if (cleaning.assigneeUid != null) {
        rightAction = Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: context.brand.muted.withOpacity(0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text('배정됨', style: TextStyle(color: context.brand.muted, fontSize: 11, fontWeight: FontWeight.w700)),
        );
      }
    }

    return Material(
      color: context.brand.panel,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: cleaning == null ? null : () => context.push('/cleaning/${cleaning.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.brand.line),
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
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${reservation.guestName}(${reservation.guestCount}명)',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 2),
                    Text(
                      '${fmt.format(reservation.checkIn)} → ${fmt.format(reservation.checkOut)}',
                      style: TextStyle(color: context.brand.muted, fontSize: 11),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    if (cleaning != null && cleaning.assigneeName != null && cleaning.assigneeName!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Row(
                          children: [
                            Icon(Icons.person, size: 12, color: isMine ? AppColors.branch1 : context.brand.muted),
                            SizedBox(width: 3),
                            Text(
                              cleaning.assigneeName!,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isMine ? AppColors.branch1 : context.brand.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (rightAction != null) ...[
                SizedBox(width: 10),
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
