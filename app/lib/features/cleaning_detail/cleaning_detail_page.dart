import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';
import '../shared/bottom_nav.dart';
import 'amenity_calc.dart';

/// 단건 청소 Provider
final cleaningProvider = StreamProvider.family<CleaningModel?, String>((ref, id) {
  final authUser = ref.watch(firebaseUserProvider).value;
  if (authUser == null) return Stream.value(null);

  return ref
      .watch(firestoreProvider)
      .collection('cleanings')
      .doc(id)
      .snapshots()
      .map((snap) => snap.exists ? CleaningModel.fromDoc(snap) : null);
});

/// 연관 예약 Provider (= 이전 게스트, 청소가 끝나면 체크아웃하는 예약)
final reservationProvider = StreamProvider.family<ReservationModel?, String>((ref, id) {
  if (id.isEmpty) return Stream.value(null);
  final authUser = ref.watch(firebaseUserProvider).value;
  if (authUser == null) return Stream.value(null);

  return ref
      .watch(firestoreProvider)
      .collection('reservations')
      .doc(id)
      .snapshots()
      .map((snap) => snap.exists ? ReservationModel.fromDoc(snap) : null);
});

/// 다음 체크인 예약 Provider (이 호점에서 청소 후 다음 체크인하는 예약)
/// 키 형식: "branchId|isoDate"
final nextReservationProvider = StreamProvider.family<ReservationModel?, String>((ref, key) {
  final authUser = ref.watch(firebaseUserProvider).value;
  if (authUser == null) return Stream.value(null);

  final parts = key.split('|');
  if (parts.length != 2) return Stream.value(null);
  final branchId = parts[0];
  final after = DateTime.tryParse(parts[1]);
  if (after == null) return Stream.value(null);

  return ref
      .watch(firestoreProvider)
      .collection('reservations')
      .where('branchId', isEqualTo: branchId)
      .where('checkIn', isGreaterThanOrEqualTo: Timestamp.fromDate(after))
      .orderBy('checkIn')
      .limit(1)
      .snapshots()
      .map((s) => s.docs.isEmpty ? null : ReservationModel.fromDoc(s.docs.first));
});

/// ③ 작업 상세 (체크리스트) - 목업 디자인 적용
class CleaningDetailPage extends ConsumerStatefulWidget {
  final String cleaningId;
  const CleaningDetailPage({super.key, required this.cleaningId});

  @override
  ConsumerState<CleaningDetailPage> createState() => _CleaningDetailPageState();
}

class _CleaningDetailPageState extends ConsumerState<CleaningDetailPage> {
  bool _claiming = false;

  @override
  Widget build(BuildContext context) {
    final cleaningAsync = ref.watch(cleaningProvider(widget.cleaningId));
    final user = ref.watch(currentUserProvider).value;
    final branches = ref.watch(branchesProvider).value ?? const <BranchModel>[];

    return Scaffold(
      appBar: AppBar(
        title: Text('청소 작업'),
        leading: IconButton(icon: Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      bottomNavigationBar: const AppBottomNav(active: BottomTab.home),
      body: cleaningAsync.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e', style: TextStyle(color: AppColors.danger))),
        data: (cleaning) {
          if (cleaning == null) {
            return Center(child: Text('청소 작업을 찾을 수 없습니다.', style: TextStyle(color: context.brand.muted)));
          }

          final branch = branches.firstWhere(
            (b) => b.id == cleaning.branchId,
            orElse: () => BranchModel(id: cleaning.branchId, name: cleaning.branchId, rooms: 0, maxOccupancy: 0, color: '#64748B', iCalSourceUrl: '', active: true),
          );
          final isMine = user != null && cleaning.assigneeUid == user.uid;
          final reservationAsync = ref.watch(reservationProvider(cleaning.reservationId));
          // 다음 체크인 예약 — 청소 당일(체크아웃) 이후 첫 예약
          final dayStart = DateTime(cleaning.scheduledDate.year, cleaning.scheduledDate.month, cleaning.scheduledDate.day);
          final nextResAsync = ref.watch(nextReservationProvider('${cleaning.branchId}|${dayStart.toIso8601String()}'));

          return SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                    children: [
                      // 호점 컬러 그라데이션 헤더
                      _BranchHeader(
                        branch: branch,
                        cleaning: cleaning,
                        prevReservation: reservationAsync.valueOrNull,
                        nextReservation: nextResAsync.valueOrNull,
                      ),
                      SizedBox(height: 14),

                      // 담당자 상태
                      _AssigneeStatus(
                        cleaning: cleaning,
                        user: user,
                        isMine: isMine,
                        claiming: _claiming,
                        onClaim: () => _claimCleaning(cleaning),
                        onRelease: () => _releaseCleaning(cleaning),
                      ),
                      SizedBox(height: 18),

                      // 어메니티 세팅 (다음 손님 기준 자동 계산, 읽기전용)
                      _AmenitySection(
                        cleaning: cleaning,
                        nextReservation: nextResAsync.valueOrNull,
                      ),
                    ],
                  ),
                ),

                // 하단 버튼 + 안내문구
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                  child: _BottomAction(
                    cleaning: cleaning,
                    isMine: isMine,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _claimCleaning(CleaningModel cleaning) async {
    setState(() => _claiming = true);
    try {
      await ref.read(functionsServiceProvider).claimCleaning(cleaning.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('배정 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  Future<void> _releaseCleaning(CleaningModel cleaning) async {
    setState(() => _claiming = true);
    try {
      await ref.read(functionsServiceProvider).releaseCleaning(cleaning.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('배정 해제 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }
}

// ===== 호점 그라데이션 헤더 =====

class _BranchHeader extends StatelessWidget {
  final BranchModel branch;
  final CleaningModel cleaning;
  final ReservationModel? prevReservation;
  final ReservationModel? nextReservation;
  const _BranchHeader({
    required this.branch,
    required this.cleaning,
    required this.prevReservation,
    required this.nextReservation,
  });

  @override
  Widget build(BuildContext context) {
    final branchColor = AppColors.branchColor(cleaning.branchId);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [branchColor.withOpacity(0.2), branchColor.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: branchColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더: 호점명 + 청소(체크아웃) 날짜 + 상태
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(branch.name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              SizedBox(width: 10),
              Text(
                DateFormat('M/d (E)', 'ko').format(cleaning.scheduledDate),
                style: TextStyle(fontSize: 12, color: context.brand.muted, fontWeight: FontWeight.w600),
              ),
              Spacer(),
              _statusPill(cleaning, branchColor),
            ],
          ),
          SizedBox(height: 12),

          // 이전 게스트 / 다음 체크인
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _GuestInfo(
                  label: '이전 게스트',
                  reservation: prevReservation,
                  showDate: '체크아웃',
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _GuestInfo(
                  label: '다음 체크인',
                  reservation: nextReservation,
                  showDate: '체크인',
                  highlight: true,
                ),
              ),
            ],
          ),

        ],
      ),
    );
  }

  Widget _statusPill(CleaningModel c, Color branchColor) {
    String text;
    Color color;
    if (c.isCompleted) {
      text = '완료';
      color = AppColors.ok;
    } else if (c.isUnassigned) {
      text = '?';
      color = const Color(0xFFFACC15);
    } else {
      text = '진행중';
      color = branchColor;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

class _GuestInfo extends StatelessWidget {
  final String label;
  final ReservationModel? reservation;
  final String showDate; // '체크아웃' or '체크인'
  final bool highlight;
  const _GuestInfo({
    required this.label,
    required this.reservation,
    required this.showDate,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final dateColor = highlight ? AppColors.warn : context.brand.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.brand.dim, fontSize: 10, fontWeight: FontWeight.w600)),
        SizedBox(height: 2),
        Text(
          r?.guestName ?? '-',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 2),
        if (r != null) ...[
          Text(
            '👤 ${r.guestCount}인',
            style: TextStyle(color: dateColor, fontSize: 11, fontWeight: FontWeight.w500),
          ),
          SizedBox(height: 2),
          Text(
            '$showDate ${DateFormat('M/d (E)', 'ko').format(showDate == '체크아웃' ? r.checkOut : r.checkIn)}',
            style: TextStyle(color: dateColor, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}

// ===== 담당자 상태 =====

class _AssigneeStatus extends StatelessWidget {
  final CleaningModel cleaning;
  final UserModel? user;
  final bool isMine;
  final bool claiming;
  final VoidCallback onClaim;
  final VoidCallback onRelease;

  const _AssigneeStatus({
    required this.cleaning,
    required this.user,
    required this.isMine,
    required this.claiming,
    required this.onClaim,
    required this.onRelease,
  });

  @override
  Widget build(BuildContext context) {
    if (cleaning.isCompleted) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.brand.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.brand.line),
      ),
      child: Row(
        children: [
          Icon(Icons.person_outline, size: 20, color: context.brand.muted),
          SizedBox(width: 10),
          Expanded(
            child: cleaning.isUnassigned
                ? Text('담당자 미지정', style: TextStyle(color: AppColors.warn, fontSize: 13, fontWeight: FontWeight.w600))
                : Text(
                    isMine ? '내가 담당 중' : '다른 청소원 담당 중',
                    style: TextStyle(
                      color: isMine ? AppColors.branch1 : context.brand.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
          if (cleaning.isUnassigned && user != null)
            SizedBox(
              height: 34,
              child: FilledButton(
                onPressed: claiming ? null : onClaim,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14)),
                child: claiming
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text('내가 할게요', style: TextStyle(fontSize: 12)),
              ),
            ),
          if (isMine && !cleaning.isCompleted)
            SizedBox(
              height: 34,
              child: OutlinedButton(
                onPressed: claiming ? null : onRelease,
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                child: claiming
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('배정 해제', style: TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}

// ===== 어메니티 세팅 (다음 손님 기준 자동 계산, 읽기전용) =====

class _AmenitySection extends StatelessWidget {
  final CleaningModel cleaning;
  final ReservationModel? nextReservation;
  const _AmenitySection({required this.cleaning, required this.nextReservation});

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final r = nextReservation;
    // 다음 손님 = 청소일(scheduledDate)에 같은 호점으로 체크인하는 예약
    final hasNext = r != null &&
        r.branchId == cleaning.branchId &&
        _sameDay(r.checkIn, cleaning.scheduledDate);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.brand.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_laundry_service_outlined, size: 18, color: AppColors.branch1),
              SizedBox(width: 8),
              Text('어메니티 세팅', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ],
          ),
          SizedBox(height: 4),
          Text(
            '다음 손님 기준으로 자동 계산된 수량입니다.',
            style: TextStyle(fontSize: 11, color: context.brand.muted),
          ),
          SizedBox(height: 12),
          if (!hasNext)
            _noNextNotice(context)
          else
            ..._buildContent(context, r),
        ],
      ),
    );
  }

  Widget _noNextNotice(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.warn.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: AppColors.warn),
              SizedBox(width: 6),
              Text('다음 예약 없음 — 기본 세팅',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.warn)),
            ],
          ),
          SizedBox(height: 6),
          Text(
            '청소일에 새로 체크인하는 예약이 없어 수량 계산을 생략합니다. 기본 세팅으로 진행해 주세요.',
            style: TextStyle(fontSize: 12, color: context.brand.muted, height: 1.4),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildContent(BuildContext context, ReservationModel r) {
    final nights = _nightsBetween(r.checkIn, r.checkOut);
    final groups = calcAmenityGroups(guests: r.guestCount, nights: nights);

    return [
      // 다음 손님 정보
      Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.warn.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.login, size: 16, color: AppColors.warn),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '${r.guestName.isEmpty ? '다음 손님' : r.guestName} · 👤 ${r.guestCount}인 · ${nights}박',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.brand.text),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      SizedBox(height: 12),
      ...groups.map((g) => _groupBlock(context, g)),
    ];
  }

  Widget _groupBlock(BuildContext context, AmenityGroup g) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(g.title,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.brand.muted)),
          SizedBox(height: 6),
          ...g.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item.name, style: TextStyle(fontSize: 13, color: context.brand.text)),
                    Text(item.qty,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.branch1)),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  int _nightsBetween(DateTime checkIn, DateTime checkOut) {
    final a = DateTime(checkIn.year, checkIn.month, checkIn.day);
    final b = DateTime(checkOut.year, checkOut.month, checkOut.day);
    final n = b.difference(a).inDays;
    return n < 1 ? 1 : n;
  }
}

// ===== 하단 액션 (당일 청소만 완료 가능) =====

class _BottomAction extends StatelessWidget {
  final CleaningModel cleaning;
  final bool isMine;
  const _BottomAction({required this.cleaning, required this.isMine});

  @override
  Widget build(BuildContext context) {
    if (cleaning.isCompleted) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.ok.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: AppColors.ok, size: 20),
            SizedBox(width: 8),
            Text(
              '완료됨 ${cleaning.completedAt != null ? DateFormat('HH:mm').format(cleaning.completedAt!) : ''}',
              style: TextStyle(color: AppColors.ok, fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (!isMine) {
      return const SizedBox.shrink();
    }

    final isToday = cleaning.isScheduledToday;
    final canProceed = isToday;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isToday)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '완료 처리는 청소 당일에만 가능합니다 '
              '(예정 ${DateFormat('M/d (E)', 'ko').format(cleaning.scheduledDate)})',
              style: TextStyle(color: AppColors.warn, fontSize: 11, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: canProceed
                ? () => context.push('/cleaning/${cleaning.id}/complete')
                : null,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              disabledBackgroundColor: const Color(0xFFCBD5E1),
              disabledForegroundColor: Colors.white,
            ),
            icon: Icon(canProceed ? Icons.check : Icons.lock, size: 18),
            label: Text(
              isToday ? '확인완료' : '오늘 예정 청소만 완료 가능',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
