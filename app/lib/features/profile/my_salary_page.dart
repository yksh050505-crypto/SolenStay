import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';

final _won = NumberFormat('#,###', 'ko');

/// 내 급여 (청소원·실장 본인용)
/// - 그 달 본인이 완료한 청소 건수 × 본인 건당 단가 = 월급
/// - 단가는 매니저가 관리자 설정에서 정한 값(config/salary)을 읽기만 함.
class MySalaryPage extends ConsumerStatefulWidget {
  const MySalaryPage({super.key});

  @override
  ConsumerState<MySalaryPage> createState() => _MySalaryPageState();
}

class _MySalaryPageState extends ConsumerState<MySalaryPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  /// 해당 월의 청소를 scheduledDate 단일 필드 range로 조회(복합 인덱스 회피).
  /// 본인 것만 클라이언트에서 필터.
  Stream<List<CleaningModel>> _stream() {
    final monthStart = DateTime(_month.year, _month.month, 1);
    final nextMonthStart = DateTime(_month.year, _month.month + 1, 1);
    return FirebaseFirestore.instance
        .collection('cleanings')
        .where('scheduledDate', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('scheduledDate', isLessThan: Timestamp.fromDate(nextMonthStart))
        .snapshots()
        .map((s) => s.docs.map(CleaningModel.fromDoc).toList());
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final salary = ref.watch(salaryConfigProvider).valueOrNull ?? const SalaryConfigModel();
    final branches = ref.watch(branchesProvider).valueOrNull ?? const <BranchModel>[];
    final uid = user?.uid;
    final rate = uid == null ? 0 : salary.rateOf(uid);

    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('내 급여', 'My salary')),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _MonthHeader(
              month: _month,
              onPrev: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              onNext: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
            ),
            Expanded(
              child: uid == null
                  ? const Center(child: CircularProgressIndicator())
                  : StreamBuilder<List<CleaningModel>>(
                      stream: _stream(),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snap.hasError) {
                          return Center(
                            child: Text('${l.t('오류', 'Error')}: ${snap.error}',
                                style: const TextStyle(color: AppColors.danger)),
                          );
                        }
                        final all = snap.data ?? const <CleaningModel>[];
                        final mine = all
                            .where((c) => c.assigneeUid == uid && c.isCompleted)
                            .toList()
                          ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));
                        final count = mine.length;
                        final total = count * rate;

                        return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            // 이번 달 월급 요약 카드
                            _SummaryCard(count: count, rate: rate, total: total, l: l),
                            const SizedBox(height: 16),
                            // 완료 청소 목록
                            Text(
                              l.t('완료한 청소', 'Completed cleanings'),
                              style: TextStyle(
                                color: context.brand.muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (mine.isEmpty)
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: context.brand.panel,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: context.brand.line),
                                ),
                                child: Center(
                                  child: Text(
                                    l.t('이 달에 완료한 청소가 없습니다', 'No completed cleanings this month'),
                                    style: TextStyle(color: context.brand.muted, fontSize: 13),
                                  ),
                                ),
                              )
                            else
                              ...mine.map((c) => _CleaningRow(cleaning: c, branches: branches, rate: rate, l: l)),
                            const SizedBox(height: 12),
                            Text(
                              l.t('기준: 청소 예정일이 해당 월에 속한 완료 건 × 건당 단가',
                                  'Basis: completed cleanings scheduled in this month × per-cleaning rate'),
                              style: TextStyle(fontSize: 11, color: context.brand.dim, height: 1.4),
                            ),
                            if (rate <= 0) ...[
                              const SizedBox(height: 8),
                              Text(
                                l.t('아직 건당 단가가 설정되지 않았습니다. 매니저에게 문의하세요.',
                                    'Your per-cleaning rate is not set yet. Please contact your manager.'),
                                style: const TextStyle(fontSize: 11, color: AppColors.warn, height: 1.4),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
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
    final prevLabel = DateFormat('M월', 'ko').format(DateTime(month.year, month.month - 1));
    final nextLabel = DateFormat('M월', 'ko').format(DateTime(month.year, month.month + 1));
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Row(
        children: [
          // 이전 달: ◀ 5월
          InkWell(
            onTap: onPrev,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left, color: context.brand.muted, size: 20),
                  Text(prevLabel, style: TextStyle(color: context.brand.muted, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                DateFormat('yyyy년 M월', 'ko').format(month),
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.brand.text),
              ),
            ),
          ),
          // 다음 달: 7월 ▶
          InkWell(
            onTap: onNext,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(nextLabel, style: TextStyle(color: context.brand.muted, fontSize: 13, fontWeight: FontWeight.w600)),
                  Icon(Icons.chevron_right, color: context.brand.muted, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final int count;
  final int rate;
  final int total;
  final L10n l;
  const _SummaryCard({required this.count, required this.rate, required this.total, required this.l});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.ok.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ok.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.ok.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.account_balance_wallet_outlined, color: AppColors.ok, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l.t('이번 달 예상 급여', 'Estimated salary this month'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _won.format(total),
                style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: AppColors.ok),
              ),
              const SizedBox(width: 4),
              Text(l.t('원', ' KRW'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ok)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${l.t('완료', 'Completed')} $count${l.t('건', '')}  ·  ${l.t('건당', 'per')} ${rate > 0 ? '${_won.format(rate)}${l.t('원', ' KRW')}' : l.t('미설정', 'not set')}',
            style: TextStyle(fontSize: 13, color: context.brand.muted, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _CleaningRow extends StatelessWidget {
  final CleaningModel cleaning;
  final List<BranchModel> branches;
  final int rate;
  final L10n l;
  const _CleaningRow({required this.cleaning, required this.branches, required this.rate, required this.l});

  @override
  Widget build(BuildContext context) {
    final branch = branches.firstWhere(
      (b) => b.id == cleaning.branchId,
      orElse: () => BranchModel(
          id: cleaning.branchId, name: cleaning.branchId, rooms: 0, maxOccupancy: 0, color: '#64748B', iCalSourceUrl: '', active: true),
    );
    final color = AppColors.branchColor(cleaning.branchId);
    final dateStr = DateFormat('M/d (E)', 'ko').format(cleaning.scheduledDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.brand.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.brand.line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(branch.name, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(dateStr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.brand.text)),
          ),
          Text(
            rate > 0 ? '+${_won.format(rate)}${l.t('원', '')}' : '-',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: rate > 0 ? AppColors.ok : context.brand.dim,
            ),
          ),
        ],
      ),
    );
  }
}
