import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';
import '../shared/bottom_nav.dart';

/// ② 오늘의 청소 (홈)
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final cleanings = ref.watch(todayCleaningsProvider);
    final branches = ref.watch(branchesProvider).value ?? const <BranchModel>[];

    final today = DateFormat('M월 d일 (E)', 'ko').format(DateTime.now());

    return Scaffold(
      bottomNavigationBar: const AppBottomNav(active: BottomTab.home),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('안녕하세요, ${user?.name ?? ""}님', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                        Text(today, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  if (user?.canManageDashboard ?? false)
                    IconButton(
                      icon: const Icon(Icons.dashboard_outlined),
                      onPressed: () => context.push('/manager'),
                      tooltip: '매니저 대시보드',
                    ),
                ],
              ),
              const SizedBox(height: 14),
              cleanings.when(
                loading: () => const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())),
                error: (e, _) => Text('오류: $e', style: const TextStyle(color: AppColors.danger)),
                data: (list) => _StatsRow(list: list),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('오늘의 청소', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: cleanings.when(
                  loading: () => const SizedBox.shrink(),
                  error: (e, _) => Text('오류: $e'),
                  data: (list) {
                    if (list.isEmpty) {
                      return const Center(child: Text('오늘 청소 일정이 없습니다.', style: TextStyle(color: AppColors.muted)));
                    }
                    return ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _TaskCard(cleaning: list[i], branches: branches),
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
        _statBox(total.toString(), '오늘 작업', AppColors.text),
        const SizedBox(width: 8),
        _statBox(done.toString(), '완료', AppColors.ok),
        const SizedBox(width: 8),
        _statBox(remaining.toString(), '남음', AppColors.warn),
      ],
    );
  }

  Widget _statBox(String num, String label, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            children: [
              Text(num, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            ],
          ),
        ),
      );
}

class _TaskCard extends ConsumerWidget {
  final CleaningModel cleaning;
  final List<BranchModel> branches;
  const _TaskCard({required this.cleaning, required this.branches});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = branches.firstWhere(
      (b) => b.id == cleaning.branchId,
      orElse: () => BranchModel(id: cleaning.branchId, name: cleaning.branchId, rooms: 0, maxOccupancy: 0, color: '#64748B', iCalSourceUrl: '', active: true),
    );
    final branchColor = AppColors.branchColor(cleaning.branchId);
    final user = ref.watch(currentUserProvider).value;
    final isMine = user != null && cleaning.assigneeUid == user.uid;

    return InkWell(
      onTap: () => context.push('/cleaning/${cleaning.id}'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
          // 호점 좌측 컬러바
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(width: 4, height: 44, decoration: BoxDecoration(color: branchColor, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(branch.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  const Text('오늘의 숙박인원', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                ],
              ),
            ),
            _statusPill(cleaning, isMine),
          ],
        ),
      ),
    );
  }

  Widget _statusPill(CleaningModel c, bool isMine) {
    if (c.isCompleted) {
      return _pill('✓ 완료', AppColors.ok);
    }
    if (c.isUnassigned) {
      return _pill('미지정', AppColors.muted);
    }
    if (isMine) {
      return _pill('내 작업', AppColors.branch1);
    }
    return _pill('진행중', AppColors.warn);
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}
