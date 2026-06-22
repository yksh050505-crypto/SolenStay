import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../core/withholding.dart';
import '../../data/models.dart';
import '../../data/services.dart';
import '../manager/manager_dashboard_page.dart' show allUsersProvider;

final _won = NumberFormat('#,###', 'ko');

/// 급여 · 월급 계산 (매니저 전용)
/// - 근무자별 '청소 1건당 단가' 설정
/// - 월급 = 그 달 완료 청소 건수 × 단가
class SalaryPage extends ConsumerStatefulWidget {
  const SalaryPage({super.key});

  @override
  ConsumerState<SalaryPage> createState() => _SalaryPageState();
}

class _SalaryPageState extends ConsumerState<SalaryPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  /// 해당 월의 청소를 scheduledDate 단일 필드 range로 조회(복합 인덱스 회피).
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

    final usersAsync = ref.watch(allUsersProvider);
    final salaryAsync = ref.watch(salaryConfigProvider);
    final showWithholding = withholdingAppliesTo(_month);

    return Scaffold(
      appBar: AppBar(
        title: const Text('급여 · 월급 계산'),
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
              child: StreamBuilder<List<CleaningModel>>(
                stream: _stream(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(
                      child: Text('오류: ${snap.error}', style: const TextStyle(color: AppColors.danger)),
                    );
                  }
                  final cleanings = snap.data ?? const <CleaningModel>[];

                  // 완료 건수 집계 (status 필터는 클라이언트에서)
                  final countByUid = <String, int>{};
                  final nameByUid = <String, String>{};
                  for (final c in cleanings) {
                    final uid = c.assigneeUid;
                    if (!c.isCompleted || uid == null) continue;
                    countByUid[uid] = (countByUid[uid] ?? 0) + 1;
                    if ((nameByUid[uid] ?? '').isEmpty && (c.assigneeName ?? '').isNotEmpty) {
                      nameByUid[uid] = c.assigneeName!;
                    }
                  }

                  return usersAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) =>
                        Center(child: Text('오류: $e', style: const TextStyle(color: AppColors.danger))),
                    data: (allUsers) {
                      final salary = salaryAsync.valueOrNull ?? const SalaryConfigModel();

                      // 근무자 = 매니저가 아닌 사용자
                      final workers = allUsers.where((u) => !u.isManager).toList();
                      final knownUids = workers.map((u) => u.uid).toSet();
                      // 매니저 uid는 급여 대상에서 제외 (청소를 완료한 적 있어도 보완 목록에 넣지 않음)
                      final managerUids = allUsers.where((u) => u.isManager).map((u) => u.uid).toSet();

                      // 행 데이터 구성
                      final rows = <_WorkerRow>[];
                      for (final u in workers) {
                        rows.add(_WorkerRow(
                          uid: u.uid,
                          name: u.name,
                          isChief: u.isChief,
                          count: countByUid[u.uid] ?? 0,
                          rate: salary.rateOf(u.uid),
                        ));
                      }
                      // 목록에 없는 uid로 완료 청소가 있으면 보완 (단 매니저는 제외)
                      for (final uid in countByUid.keys) {
                        if (knownUids.contains(uid)) continue;
                        if (managerUids.contains(uid)) continue;
                        final nm = nameByUid[uid];
                        rows.add(_WorkerRow(
                          uid: uid,
                          name: (nm != null && nm.isNotEmpty) ? nm : '(알 수 없음)',
                          isChief: false,
                          count: countByUid[uid] ?? 0,
                          rate: salary.rateOf(uid),
                          unknown: true,
                        ));
                      }
                      rows.sort((a, b) => a.name.compareTo(b.name));

                      final totalCount = rows.fold<int>(0, (s, r) => s + r.count);
                      final totalPay = rows.fold<int>(0, (s, r) => s + r.count * r.rate);
                      final totalTax =
                          rows.fold<int>(0, (s, r) => s + Withholding.of(r.count * r.rate).tax);
                      final totalNet = totalPay - totalTax;

                      if (rows.isEmpty) {
                        return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          children: [
                            _emptyBox('등록된 근무자가 없습니다'),
                          ],
                        );
                      }

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        children: [
                          ...rows.map((r) => _WorkerCard(
                                row: r,
                                onSetRate: () => _showRateDialog(r, salary),
                                showWithholding: showWithholding,
                              )),
                          const SizedBox(height: 8),
                          _TotalCard(
                            totalCount: totalCount,
                            totalPay: totalPay,
                            totalTax: totalTax,
                            totalNet: totalNet,
                            showWithholding: showWithholding,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '기준: 청소 예정일이 해당 월에 속한 완료 건 × 건당 단가',
                            style: TextStyle(fontSize: 11, color: context.brand.dim, height: 1.4),
                          ),
                          if (showWithholding)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '원천세 3.3%(사업소득) 공제 후 실지급액 · 2026년 7월 지급분부터 적용',
                                style: TextStyle(fontSize: 11, color: context.brand.dim, height: 1.4),
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyBox(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.muted.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(text, style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }

  /// 근무자 1명의 건당 단가 설정 다이얼로그.
  Future<void> _showRateDialog(_WorkerRow row, SalaryConfigModel current) async {
    final ctrl = TextEditingController(text: row.rate > 0 ? row.rate.toString() : '');
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.payments_outlined, color: AppColors.ok, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text('${row.name} 단가 설정')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '청소 1건당 지급할 단가(원)를 입력하세요.\n0 또는 빈값은 "미설정"으로 처리됩니다.',
                style: TextStyle(fontSize: 12, color: context.brand.muted, height: 1.5),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '건당 단가',
                  suffixText: '원',
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('취소')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.ok),
              onPressed: saving
                  ? null
                  : () async {
                      final value = int.tryParse(ctrl.text.trim()) ?? 0;
                      if (value < 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('0 이상으로 입력하세요')),
                        );
                        return;
                      }
                      setLocal(() => saving = true);
                      try {
                        // 다른 사람 단가 보존: 전체 맵을 다시 써야 함
                        // (dot-notation은 set+merge에서 중첩 경로로 해석되지 않음).
                        final newMap = Map<String, int>.from(current.ratePerCleaning);
                        newMap[row.uid] = value;
                        await FirebaseFirestore.instance.collection('config').doc('salary').set({
                          'ratePerCleaning': newMap,
                          'updatedAt': FieldValue.serverTimestamp(),
                        }, SetOptions(merge: true));
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${row.name} 단가 ${_won.format(value)}원 저장됨'),
                              backgroundColor: AppColors.ok,
                            ),
                          );
                        }
                      } catch (e) {
                        setLocal(() => saving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('저장'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 근무자 1명의 계산 결과를 담는 뷰 모델.
class _WorkerRow {
  final String uid;
  final String name;
  final bool isChief;
  final int count;
  final int rate;
  final bool unknown;
  _WorkerRow({
    required this.uid,
    required this.name,
    required this.isChief,
    required this.count,
    required this.rate,
    this.unknown = false,
  });

  int get pay => count * rate;
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

class _WorkerCard extends StatelessWidget {
  final _WorkerRow row;
  final VoidCallback onSetRate;
  final bool showWithholding;
  const _WorkerCard({required this.row, required this.onSetRate, this.showWithholding = false});

  @override
  Widget build(BuildContext context) {
    final roleLabel = row.unknown ? '미등록' : (row.isChief ? '실장' : '청소원');
    final roleColor = row.unknown ? context.brand.dim : (row.isChief ? AppColors.warn : AppColors.branch1);
    final noRate = row.rate <= 0;
    final applyWithholding = showWithholding && row.pay > 0;
    final wh = applyWithholding ? Withholding.of(row.pay) : null;
    final payLabel = applyWithholding ? '실지급액' : '월급';
    final payValue = applyWithholding ? wh!.net : row.pay;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
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
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.name,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: roleColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        roleLabel,
                        style: TextStyle(color: roleColor, fontSize: 10, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: onSetRate,
                icon: const Icon(Icons.tune, size: 14),
                label: const Text('단가 설정'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ok,
                  side: const BorderSide(color: AppColors.ok, width: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _stat(context, label: '완료', value: '${row.count}건'),
              ),
              Expanded(
                child: noRate
                    ? _stat(context, label: '건당 단가', value: '미설정', valueColor: AppColors.warn)
                    : _stat(context, label: '건당 단가', value: '${_won.format(row.rate)}원'),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(payLabel, style: TextStyle(fontSize: 11, color: context.brand.muted)),
                    const SizedBox(height: 2),
                    Text(
                      '${_won.format(payValue)}원',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: payValue > 0 ? AppColors.ok : context.brand.dim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (wh != null) ...[
            const SizedBox(height: 8),
            Text(
              '총지급 ${_won.format(wh.gross)}원 · 원천세 -${_won.format(wh.tax)}원',
              style: TextStyle(fontSize: 11, color: context.brand.dim),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, {required String label, required String value, Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: context.brand.muted)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: valueColor ?? context.brand.text,
          ),
        ),
      ],
    );
  }
}

class _TotalCard extends StatelessWidget {
  final int totalCount;
  final int totalPay;
  final int totalTax;
  final int totalNet;
  final bool showWithholding;
  const _TotalCard({
    required this.totalCount,
    required this.totalPay,
    this.totalTax = 0,
    this.totalNet = 0,
    this.showWithholding = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.ok.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.ok.withOpacity(0.3)),
      ),
      child: showWithholding ? _buildWithholding(context) : _buildSimple(context),
    );
  }

  Widget _buildSimple(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.ok.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.summarize_outlined, color: AppColors.ok, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('전체 월급 합계', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 2),
              Text(
                '총 완료 $totalCount건',
                style: TextStyle(fontSize: 11, color: context.brand.muted),
              ),
            ],
          ),
        ),
        Text(
          '${_won.format(totalPay)}원',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.ok),
        ),
      ],
    );
  }

  Widget _buildWithholding(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.ok.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.summarize_outlined, color: AppColors.ok, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('전체 급여 합계', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    '총 완료 $totalCount건',
                    style: TextStyle(fontSize: 11, color: context.brand.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _totalLine(context, '총지급액 합계', '${_won.format(totalPay)}원',
            color: context.brand.text, strong: false),
        const SizedBox(height: 6),
        _totalLine(context, '원천세 합계', '-${_won.format(totalTax)}원',
            color: context.brand.muted, strong: false),
        const SizedBox(height: 6),
        _totalLine(context, '실지급액 합계', '${_won.format(totalNet)}원',
            color: AppColors.ok, strong: true),
      ],
    );
  }

  Widget _totalLine(BuildContext context, String label, String value,
      {required Color color, required bool strong}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: strong ? 13 : 12,
            fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            color: strong ? color : context.brand.muted,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: strong ? 18 : 13,
            fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
