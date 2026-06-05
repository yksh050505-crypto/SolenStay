import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';

/// 매니저 전용 — 큰 달력 뷰에서 예약 추가/수정/삭제
class ReservationManagementPage extends ConsumerStatefulWidget {
  const ReservationManagementPage({super.key});

  @override
  ConsumerState<ReservationManagementPage> createState() => _ReservationManagementPageState();
}

class _ReservationManagementPageState extends ConsumerState<ReservationManagementPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  Stream<List<ReservationModel>> _stream() {
    final start = DateTime(_month.year, _month.month - 1, 1);
    final end = DateTime(_month.year, _month.month + 2, 1);
    return FirebaseFirestore.instance
        .collection('reservations')
        .where('checkOut', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('checkOut', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .map((s) => s.docs.map(ReservationModel.fromDoc).toList());
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(currentUserProvider);
    if (userAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final user = userAsync.value;
    if (user == null || !user.isManager) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('권한 없음'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        ),
        body: Center(child: Text('매니저만 접근 가능합니다', style: TextStyle(color: context.brand.muted))),
      );
    }

    final branches = ref.watch(branchesProvider).valueOrNull ?? const <BranchModel>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('달력 일정 관리'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditDialog(branches: branches),
        icon: const Icon(Icons.add),
        label: const Text('예약 추가'),
      ),
      body: SafeArea(
        child: StreamBuilder<List<ReservationModel>>(
          stream: _stream(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('오류: ${snap.error}', style: const TextStyle(color: AppColors.danger)));
            }
            final reservations = snap.data ?? const <ReservationModel>[];

            return Column(
              children: [
                _MonthHeader(
                  month: _month,
                  onPrev: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                  onNext: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                ),
                const _WeekdayRow(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 80),
                    child: _MonthGrid(
                      month: _month,
                      reservations: reservations,
                      onPillTap: (r) => _showEditDialog(branches: branches, existing: r),
                      onDayTap: (day) => _showEditDialog(branches: branches, defaultDate: day),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showEditDialog({
    required List<BranchModel> branches,
    ReservationModel? existing,
    DateTime? defaultDate,
  }) async {
    if (branches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('호점 정보가 로드되지 않았습니다')),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => _EditReservationDialog(
        branches: branches,
        existing: existing,
        defaultDate: defaultDate,
      ),
    );
  }
}

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
          IconButton(onPressed: onPrev, icon: Icon(Icons.chevron_left, color: context.brand.text), iconSize: 22),
          Expanded(
            child: Center(
              child: Text(
                DateFormat('yyyy년 M월', 'ko').format(month),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.brand.text),
              ),
            ),
          ),
          IconButton(onPressed: onNext, icon: Icon(Icons.chevron_right, color: context.brand.text), iconSize: 22),
        ],
      ),
    );
  }
}

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

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final List<ReservationModel> reservations;
  final ValueChanged<ReservationModel> onPillTap;
  final ValueChanged<DateTime> onDayTap;
  const _MonthGrid({
    required this.month,
    required this.reservations,
    required this.onPillTap,
    required this.onDayTap,
  });

  List<List<DateTime>> _buildWeeks() {
    final first = DateTime(month.year, month.month, 1);
    final firstSunOffset = first.weekday % 7;
    final start = first.subtract(Duration(days: firstSunOffset));

    final weeks = <List<DateTime>>[];
    var cursor = start;
    while (true) {
      final week = List.generate(7, (i) => cursor.add(Duration(days: i)));
      final hasMonthDay = week.any((d) => d.month == month.month && d.year == month.year);
      if (hasMonthDay) weeks.add(week);
      cursor = cursor.add(const Duration(days: 7));
      if (!hasMonthDay && weeks.isNotEmpty) break;
      if (weeks.length >= 6) break;
    }
    return weeks;
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _buildWeeks();
    return LayoutBuilder(
      builder: (context, constraints) {
        // 1. 한 달 전체에서 가장 많은 트랙을 가진 주 찾기 → 모든 row 통일
        int maxTrackCount = 1;
        for (final week in weeks) {
          final pills = _WeekRow.layoutPillsFor(
            days: week,
            month: month,
            reservations: reservations,
          );
          if (pills.isNotEmpty) {
            final c = pills.map((p) => p.track).fold<int>(0, (m, v) => v > m ? v : m) + 1;
            if (c > maxTrackCount) maxTrackCount = c;
          }
        }

        // 2. 트랙 수에 맞는 필요 height 계산
        const pillH = 22.0;
        const pillVGap = 4.0;
        const pillBottomBase = 10.0;
        const topPadForDate = 30.0; // 날짜 숫자 + 여백
        final tracksTotalH = pillH * maxTrackCount + pillVGap * (maxTrackCount - 1);
        final neededRowH = pillBottomBase + tracksTotalH + topPadForDate;

        // 3. 화면 균등 분배 후보 vs 필요 height → 큰 쪽 채택
        final equalRowH = constraints.maxHeight / weeks.length;
        final rowH = neededRowH > equalRowH ? neededRowH : equalRowH.clamp(80.0, 200.0);

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: weeks.map((week) => _WeekRow(
              days: week,
              month: month,
              reservations: reservations,
              rowHeight: rowH,
              onPillTap: onPillTap,
              onDayTap: onDayTap,
            )).toList(),
          ),
        );
      },
    );
  }
}

class _WeekRow extends StatelessWidget {
  final List<DateTime> days;
  final DateTime month;
  final List<ReservationModel> reservations;
  final double rowHeight;
  final ValueChanged<ReservationModel> onPillTap;
  final ValueChanged<DateTime> onDayTap;
  const _WeekRow({
    required this.days,
    required this.month,
    required this.reservations,
    required this.rowHeight,
    required this.onPillTap,
    required this.onDayTap,
  });

  static DateTime _maxDay(DateTime a, DateTime b) => a.isAfter(b) ? a : b;
  static DateTime _minDay(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// 한 주의 pill 레이아웃 + 트랙 배정. _MonthGrid에서 미리 호출하여
  /// 모든 주의 최대 트랙 수를 알아내고 row 높이를 통일할 때 사용.
  static List<_PillLayout> layoutPillsFor({
    required List<DateTime> days,
    required DateTime month,
    required List<ReservationModel> reservations,
  }) {
    final weekStart = DateTime(days.first.year, days.first.month, days.first.day);
    final weekEnd = DateTime(days.last.year, days.last.month, days.last.day);
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    final visStart = _maxDay(weekStart, monthStart);
    final visEnd = _minDay(weekEnd, monthEnd);

    final visibleRes = <_ResRange>[];
    for (final r in reservations) {
      final inDay = DateTime(r.checkIn.year, r.checkIn.month, r.checkIn.day);
      final outDay = DateTime(r.checkOut.year, r.checkOut.month, r.checkOut.day);
      if (outDay.isBefore(visStart) || inDay.isAfter(visEnd)) continue;

      final clampedIn = _maxDay(inDay, visStart);
      final clampedOut = _minDay(outDay, visEnd);
      final isStartCap = _sameDay(clampedIn, inDay);
      final isEndCap = _sameDay(clampedOut, outDay);
      final isMonthClippedStart = !isStartCap && inDay.isBefore(monthStart);
      final isMonthClippedEnd = !isEndCap && outDay.isAfter(monthEnd);
      final startCol = clampedIn.difference(weekStart).inDays;
      final endCol = clampedOut.difference(weekStart).inDays;
      visibleRes.add(_ResRange(
        reservation: r, startCol: startCol, endCol: endCol,
        isStartCap: isStartCap, isEndCap: isEndCap,
        isMonthClippedStart: isMonthClippedStart, isMonthClippedEnd: isMonthClippedEnd,
      ));
    }

    // 호점별로 트랙 영역을 분리한다.
    // 1호점은 항상 윗쪽, 2호점 가운데, 3호점 아래쪽 → 시각적으로 호점별 줄 구분.
    // 같은 호점 내에서만 중복 시 트랙 추가(아래 방향).
    const orderedBranches = ['branch1', 'branch2', 'branch3'];

    final byBranch = <String, List<_ResRange>>{};
    for (final r in visibleRes) {
      byBranch.putIfAbsent(r.reservation.branchId, () => []).add(r);
    }

    final result = <_PillLayout>[];
    int trackOffset = 0;

    void assignGroup(List<_ResRange> list) {
      list.sort((a, b) {
        final s = a.startCol.compareTo(b.startCol);
        if (s != 0) return s;
        return a.reservation.id.compareTo(b.reservation.id);
      });
      final trackLastCol = <int>[];
      int maxLocalTrack = 0;
      for (final res in list) {
        var t = 0;
        while (t < trackLastCol.length && trackLastCol[t] >= res.startCol) {
          t++;
        }
        if (t == trackLastCol.length) {
          trackLastCol.add(res.endCol);
        } else {
          trackLastCol[t] = res.endCol;
        }
        if (t > maxLocalTrack) maxLocalTrack = t;
        result.add(_PillLayout(range: res, track: trackOffset + t));
      }
      trackOffset += maxLocalTrack + 1;
    }

    // 알려진 호점 순서대로 처리
    for (final bid in orderedBranches) {
      final list = byBranch.remove(bid);
      if (list == null || list.isEmpty) continue;
      assignGroup(list);
    }
    // 그 외 호점이 있으면 뒤에 붙임
    for (final entry in byBranch.entries) {
      assignGroup(entry.value);
    }

    return result;
  }

  List<_PillLayout> _layoutPills() => layoutPillsFor(
        days: days,
        month: month,
        reservations: reservations,
      );

  @override
  Widget build(BuildContext context) {
    final pills = _layoutPills();
    final trackCount = pills.isEmpty ? 1 : pills.map((p) => p.track).fold<int>(0, (m, v) => v > m ? v : m) + 1;
    const pillH = 22.0;
    const pillVGap = 4.0;
    // pill 들은 셀 하단부터 위로 쌓기 → 날짜 숫자(좌상단)와 안 겹침
    const pillBottomBase = 10.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 6.0;
        final cellW = (constraints.maxWidth - gap * 6) / 7;

        return SizedBox(
          height: rowHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
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
                        height: rowHeight,
                        onTap: () => onDayTap(day),
                      ),
                    ),
                  );
                }),
              ),
              ...pills.map((p) {
                final r = p.range;
                final left = (r.isStartCap || r.isMonthClippedStart)
                    ? r.startCol * (cellW + gap) + cellW / 2
                    : 0.0;
                final right = (r.isEndCap || r.isMonthClippedEnd)
                    ? r.endCol * (cellW + gap) + cellW / 2
                    : 7 * (cellW + gap) - gap;
                final width = right - left;
                final invTrack = (trackCount - 1) - p.track;
                final bottom = pillBottomBase + invTrack * (pillH + pillVGap);
                final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
                final coDay = DateTime(r.reservation.checkOut.year, r.reservation.checkOut.month, r.reservation.checkOut.day);
                final isPast = coDay.isBefore(today);
                if (isPast) return const SizedBox.shrink();
                // 한 주의 시작 셀(일요일) — 이전 주에서 이어진 경우라도 텍스트 재표시
                final isWeekStart = r.startCol == 0 && !r.isStartCap;
                return Positioned(
                  left: left, width: width, bottom: bottom, height: pillH,
                  child: GestureDetector(
                    onTap: () => onPillTap(r.reservation),
                    child: _Pill(
                      reservation: r.reservation,
                      isStartCap: r.isStartCap,
                      isEndCap: r.isEndCap,
                      isWeekStart: isWeekStart,
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
  final int startCol;
  final int endCol;
  final bool isStartCap;
  final bool isEndCap;
  final bool isMonthClippedStart;
  final bool isMonthClippedEnd;
  _ResRange({
    required this.reservation, required this.startCol, required this.endCol,
    required this.isStartCap, required this.isEndCap,
    this.isMonthClippedStart = false, this.isMonthClippedEnd = false,
  });
}

class _PillLayout {
  final _ResRange range;
  final int track;
  _PillLayout({required this.range, required this.track});
}

class _DayCard extends StatelessWidget {
  final DateTime day;
  final DateTime month;
  final double height;
  final VoidCallback onTap;
  const _DayCard({required this.day, required this.month, required this.height, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isThisMonth = day.month == month.month && day.year == month.year;
    if (!isThisMonth) return SizedBox(height: height);

    final isWeekend = day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    final today = DateTime.now();
    final isToday = day.year == today.year && day.month == today.month && day.day == today.day;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height - 6,
        margin: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: context.brand.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isToday ? AppColors.branch1 : context.brand.line,
            width: isToday ? 1.2 : 0.8,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                color: isToday ? AppColors.branch1 : (isWeekend ? AppColors.danger : context.brand.text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final ReservationModel reservation;
  final bool isStartCap;
  final bool isEndCap;
  /// 한 주의 시작 셀(일요일)에 위치한 pill이면 true.
  /// isStartCap이 false라도 (이전 주에서 이어진 pill) 다음 주 첫 셀에 텍스트 표시.
  final bool isWeekStart;
  const _Pill({required this.reservation, required this.isStartCap, required this.isEndCap, this.isWeekStart = false});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.branchColor(reservation.branchId);
    final radius = BorderRadius.only(
      topLeft: Radius.circular(isStartCap ? 11 : 0),
      bottomLeft: Radius.circular(isStartCap ? 11 : 0),
      topRight: Radius.circular(isEndCap ? 11 : 0),
      bottomRight: Radius.circular(isEndCap ? 11 : 0),
    );
    final borderSide = BorderSide(color: Colors.black.withOpacity(0.25), width: 1);
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: radius,
          border: Border(
            top: borderSide,
            bottom: borderSide,
            left: isStartCap ? borderSide : BorderSide.none,
            right: isEndCap ? borderSide : BorderSide.none,
          ),
        ),
        padding: EdgeInsets.only(left: isStartCap ? 8 : 0, right: isEndCap ? 8 : 0),
        alignment: Alignment.centerLeft,
        child: isStartCap
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                  Flexible(
                    child: Text(
                      '${reservation.guestName}(${reservation.guestCount}명)',
                      style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                      maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false,
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
// 편집 다이얼로그
// ═══════════════════════════════════════════════════════════════════

class _EditReservationDialog extends StatefulWidget {
  final List<BranchModel> branches;
  final ReservationModel? existing;
  final DateTime? defaultDate;
  const _EditReservationDialog({required this.branches, this.existing, this.defaultDate});

  @override
  State<_EditReservationDialog> createState() => _EditReservationDialogState();
}

class _EditReservationDialogState extends State<_EditReservationDialog> {
  late String _branchId;
  late String _ota;
  late TextEditingController _name;
  late TextEditingController _count;
  late DateTime _checkIn;
  late DateTime _checkOut;
  bool _saving = false;

  static const _otaOptions = ['airbnb', 'booking', 'agoda', 'unknown'];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _branchId = e?.branchId ?? widget.branches.first.id;
    _ota = e?.ota ?? 'airbnb';
    _name = TextEditingController(text: e?.guestName ?? '');
    _count = TextEditingController(text: (e?.guestCount ?? 2).toString());
    final base = widget.defaultDate ?? DateTime.now();
    _checkIn = e?.checkIn ?? DateTime(base.year, base.month, base.day, 15);
    _checkOut = e?.checkOut ?? DateTime(base.year, base.month, base.day + 1, 11);
  }

  @override
  void dispose() {
    _name.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isCheckIn) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isCheckIn ? _checkIn : _checkOut,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    setState(() {
      if (isCheckIn) {
        _checkIn = DateTime(picked.year, picked.month, picked.day, 15);
        if (!_checkOut.isAfter(_checkIn)) {
          _checkOut = DateTime(picked.year, picked.month, picked.day + 1, 11);
        }
      } else {
        _checkOut = DateTime(picked.year, picked.month, picked.day, 11);
      }
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('게스트명을 입력하세요')));
      return;
    }
    final count = int.tryParse(_count.text.trim()) ?? 0;
    if (count <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('인원을 정확히 입력하세요')));
      return;
    }
    if (!_checkOut.isAfter(_checkIn)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('체크아웃은 체크인 이후여야 합니다')));
      return;
    }

    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      final data = {
        'branchId': _branchId, 'ota': _ota,
        'guestName': _name.text.trim(), 'guestCount': count,
        'checkIn': Timestamp.fromDate(_checkIn),
        'checkOut': Timestamp.fromDate(_checkOut),
      };

      if (widget.existing != null) {
        await db.collection('reservations').doc(widget.existing!.id).update(data);
        await db.collection('cleanings').doc(widget.existing!.id).set({
          'branchId': _branchId,
          'scheduledDate': Timestamp.fromDate(_checkOut),
        }, SetOptions(merge: true));
      } else {
        final ref = await db.collection('reservations').add({
          ...data, 'createdAt': FieldValue.serverTimestamp(),
        });
        await db.collection('cleanings').doc(ref.id).set({
          'branchId': _branchId, 'reservationId': ref.id,
          'scheduledDate': Timestamp.fromDate(_checkOut),
          'assigneeUid': null, 'assigneeName': null, 'assignedAt': null,
          'status': 'unassigned', 'checklist': [], 'startedAt': null,
          'completedAt': null, 'photoUrls': [], 'memo': '',
          'forceAssigned': false, 'reminderSent': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.existing != null ? '수정 완료' : '추가 완료'), backgroundColor: AppColors.ok),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (widget.existing == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('예약 삭제'),
        content: Text('${widget.existing!.guestName} 예약을 삭제하시겠습니까?\n연관 청소 작업도 함께 삭제됩니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      await db.collection('reservations').doc(widget.existing!.id).delete();
      await db.collection('cleanings').doc(widget.existing!.id).delete();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제 완료'), backgroundColor: AppColors.ok),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final fmt = DateFormat('M월 d일 (E)', 'ko');
    final nights = _checkOut.difference(_checkIn).inDays.clamp(0, 999);

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      contentPadding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      title: Text(isEdit ? '예약 수정' : '예약 추가'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 호점 + OTA — 한 줄
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _branchId,
                    decoration: const InputDecoration(labelText: '호점', isDense: true),
                    items: widget.branches
                        .map((b) => DropdownMenuItem(value: b.id, child: Text(b.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _branchId = v!),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _ota,
                    decoration: const InputDecoration(labelText: 'OTA', isDense: true),
                    items: _otaOptions
                        .map((o) => DropdownMenuItem(value: o, child: Text(o.toUpperCase())))
                        .toList(),
                    onChanged: (v) => setState(() => _ota = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 게스트명 + 인원 — 한 줄
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: '게스트명', isDense: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _count,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '인원', isDense: true, suffixText: '명'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // 체크인 / 체크아웃 — 한 줄 + 박스 안에 정리
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.brand.panel2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.brand.line),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _DateField(
                          label: '체크인',
                          dateText: fmt.format(_checkIn),
                          onTap: () => _pickDate(true),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.arrow_forward, size: 14, color: context.brand.dim),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _DateField(
                          label: '체크아웃',
                          dateText: fmt.format(_checkOut),
                          onTap: () => _pickDate(false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$nights박',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: nights > 0 ? AppColors.branch1 : AppColors.danger,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              if (isEdit)
                TextButton.icon(
                  onPressed: _saving ? null : _delete,
                  icon: const Icon(Icons.delete_outline, size: 14, color: AppColors.danger),
                  label: const Text('삭제', style: TextStyle(color: AppColors.danger, fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              const Spacer(),
              TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('취소')),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '저장중...' : (isEdit ? '수정' : '추가')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 체크인/체크아웃 한 칸 — 라벨 + 날짜 + 탭 영역
class _DateField extends StatelessWidget {
  final String label;
  final String dateText;
  final VoidCallback onTap;
  const _DateField({required this.label, required this.dateText, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: context.brand.muted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Row(
              children: [
                Icon(Icons.calendar_today, size: 12, color: context.brand.dim),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    dateText,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.brand.text),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
