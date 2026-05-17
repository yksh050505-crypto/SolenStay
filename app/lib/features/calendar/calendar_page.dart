import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';
import '../shared/bottom_nav.dart';

/// ⑤ 캘린더 — 호점별 색상 바 (체크인~체크아웃 연결) + 다가오는 청소
class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
  }

  /// 특정 날짜에 머무는 모든 예약 찾기 (체크인 <= day <= 체크아웃)
  /// 체크아웃 날까지 포함해서 바가 시각적으로 이어지도록 함
  List<ReservationModel> _reservationsOnDay(List<ReservationModel> all, DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    return all.where((r) {
      final inStart = DateTime(r.checkIn.year, r.checkIn.month, r.checkIn.day);
      final outStart = DateTime(r.checkOut.year, r.checkOut.month, r.checkOut.day);
      return !dayStart.isBefore(inStart) && !dayStart.isAfter(outStart);
    }).toList()
      ..sort((a, b) => a.branchId.compareTo(b.branchId));
  }

  /// 특정 날짜가 체크인 첫날인지, 체크아웃 마지막날인지 판단
  _DayPosition _positionOnDay(ReservationModel r, DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final inStart = DateTime(r.checkIn.year, r.checkIn.month, r.checkIn.day);
    final outStart = DateTime(r.checkOut.year, r.checkOut.month, r.checkOut.day);
    final isFirst = dayStart.isAtSameMomentAs(inStart);
    final isLast = dayStart.isAtSameMomentAs(outStart);
    if (isFirst && isLast) return _DayPosition.single;
    if (isFirst) return _DayPosition.start;
    if (isLast) return _DayPosition.end;
    return _DayPosition.middle;
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

          return Column(
            children: [
              // 캘린더
              TableCalendar<ReservationModel>(
                firstDay: DateTime.now().subtract(const Duration(days: 30)),
                lastDay: DateTime.now().add(const Duration(days: 120)),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                onDaySelected: (selected, focused) {
                  setState(() {
                    _selectedDay = selected;
                    _focusedDay = focused;
                  });
                },
                onPageChanged: (focused) => _focusedDay = focused,
                eventLoader: (day) => _reservationsOnDay(reservations, day),
                locale: 'ko_KR',
                startingDayOfWeek: StartingDayOfWeek.sunday,
                headerStyle: const HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  leftChevronIcon: Icon(Icons.chevron_left, color: AppColors.text),
                  rightChevronIcon: Icon(Icons.chevron_right, color: AppColors.text),
                ),
                daysOfWeekHeight: 26,
                rowHeight: 56,
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600),
                  weekendStyle: TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                calendarStyle: const CalendarStyle(
                  cellMargin: EdgeInsets.all(2),
                  outsideDaysVisible: false,
                  defaultDecoration: BoxDecoration(),
                  weekendTextStyle: TextStyle(color: AppColors.danger),
                  defaultTextStyle: TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600),
                  markersMaxCount: 0, // 기본 점 마커 비활성
                ),
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, day, _) => _buildDayCell(day, reservations, selected: false, today: false),
                  todayBuilder: (context, day, _) => _buildDayCell(day, reservations, selected: false, today: true),
                  selectedBuilder: (context, day, _) => _buildDayCell(day, reservations, selected: true, today: isSameDay(day, DateTime.now())),
                  outsideBuilder: (context, day, _) => Opacity(
                    opacity: 0.35,
                    child: _buildDayCell(day, reservations, selected: false, today: false),
                  ),
                  // 마커는 우리가 셀 안에서 직접 그리므로 빈 위젯
                  markerBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              Container(height: 1, color: AppColors.line),

              // 선택된 날짜 헤더
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 4),
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

              // 선택된 날짜의 예약 + 다가오는 청소
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
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 날짜 셀 렌더링 — 호점별 색상 바를 좌우로 연결되도록 그림
  Widget _buildDayCell(DateTime day, List<ReservationModel> all, {required bool selected, required bool today}) {
    final dayReservations = _reservationsOnDay(all, day);

    return Container(
      decoration: BoxDecoration(
        color: selected ? AppColors.branch1.withOpacity(0.08) : null,
        border: today && !selected ? Border.all(color: AppColors.branch1, width: 1.5) : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: today || selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? AppColors.branch1
                      : today
                          ? AppColors.branch1
                          : (day.weekday == DateTime.saturday || day.weekday == DateTime.sunday)
                              ? AppColors.danger
                              : AppColors.text,
                ),
              ),
            ),
          ),
          const Spacer(),
          // 호점별 바 (최대 3개)
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 2, right: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: dayReservations.take(3).map((r) {
                final pos = _positionOnDay(r, day);
                return _branchBar(r.branchId, pos);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// 호점 색상 바 (좌/우 둥글기는 위치에 따라)
  Widget _branchBar(String branchId, _DayPosition pos) {
    final color = AppColors.branchColor(branchId);
    // 끝과 끝은 둥글게, 중간은 직각으로 연결
    final left = pos == _DayPosition.start || pos == _DayPosition.single;
    final right = pos == _DayPosition.end || pos == _DayPosition.single;

    return Container(
      height: 4,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(left ? 2 : 0),
          bottomLeft: Radius.circular(left ? 2 : 0),
          topRight: Radius.circular(right ? 2 : 0),
          bottomRight: Radius.circular(right ? 2 : 0),
        ),
      ),
    );
  }
}

enum _DayPosition { start, middle, end, single }

/// 하단 — 선택일 예약 + 다가오는 청소
class _BottomList extends StatelessWidget {
  final List<ReservationModel> selectedReservations;
  final List<ReservationModel> allReservations;
  final List<CleaningModel> cleanings;
  final List<BranchModel> branches;
  final WidgetRef ref;
  const _BottomList({
    required this.selectedReservations,
    required this.allReservations,
    required this.cleanings,
    required this.branches,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
      children: [
        // 선택일 숙박 예약
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

        const SizedBox(height: 14),
        const Text(
          '다가오는 청소',
          style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),

        if (cleanings.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text('다가오는 청소가 없습니다', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            ),
          )
        else
          ...cleanings.take(5).map((c) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _CleaningCard(cleaning: c, allReservations: allReservations, branches: branches),
              )),
      ],
    );
  }
}

class _ReservationCard extends StatelessWidget {
  final ReservationModel reservation;
  final List<BranchModel> branches;
  const _ReservationCard({required this.reservation, required this.branches});

  @override
  Widget build(BuildContext context) {
    final branch = branches.firstWhere(
      (b) => b.id == reservation.branchId,
      orElse: () => BranchModel(id: reservation.branchId, name: reservation.branchId, rooms: 0, maxOccupancy: 0, color: '#64748B', iCalSourceUrl: '', active: true),
    );
    final branchColor = AppColors.branchColor(reservation.branchId);
    final nights = reservation.checkOut.difference(reservation.checkIn).inDays;
    final fmt = DateFormat('M/d (E)', 'ko');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
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
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${reservation.guestName} · 👤 ${reservation.guestCount}인',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  '${fmt.format(reservation.checkIn)} → ${fmt.format(reservation.checkOut)} · ${nights}박',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            reservation.ota.toUpperCase(),
            style: const TextStyle(color: AppColors.dim, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _CleaningCard extends StatelessWidget {
  final CleaningModel cleaning;
  final List<ReservationModel> allReservations;
  final List<BranchModel> branches;
  const _CleaningCard({required this.cleaning, required this.allReservations, required this.branches});

  @override
  Widget build(BuildContext context) {
    final branch = branches.firstWhere(
      (b) => b.id == cleaning.branchId,
      orElse: () => BranchModel(id: cleaning.branchId, name: cleaning.branchId, rooms: 0, maxOccupancy: 0, color: '#64748B', iCalSourceUrl: '', active: true),
    );
    final branchColor = AppColors.branchColor(cleaning.branchId);

    // 청소와 연결된 예약 (체크인/체크아웃 표시용)
    final res = allReservations.firstWhere(
      (r) => r.id == cleaning.reservationId,
      orElse: () => ReservationModel(
        id: '',
        branchId: cleaning.branchId,
        ota: 'unknown',
        guestName: '',
        guestCount: 0,
        checkIn: cleaning.scheduledDate,
        checkOut: cleaning.scheduledDate,
      ),
    );

    final hasReservation = res.id.isNotEmpty;
    final nights = hasReservation ? res.checkOut.difference(res.checkIn).inDays : 0;
    final fmtFull = DateFormat('M/d (E)', 'ko');

    return InkWell(
      onTap: () => context.push('/cleaning/${cleaning.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fmtFull.format(cleaning.scheduledDate),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  if (hasReservation)
                    Text(
                      '${fmtFull.format(res.checkIn)} 체크인 · ${nights}박 후 청소${res.ota == 'unknown' ? '' : ' · ${res.ota.toUpperCase()}'}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 11),
                    )
                  else
                    Text(
                      cleaning.isCompleted ? '완료' : cleaning.isUnassigned ? '미지정' : '배정됨',
                      style: TextStyle(
                        color: cleaning.isCompleted ? AppColors.ok : cleaning.isUnassigned ? AppColors.warn : AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              cleaning.isCompleted ? Icons.check_circle : Icons.chevron_right,
              color: cleaning.isCompleted ? AppColors.ok : AppColors.dim,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
