import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/services.dart';

/// ⑦ 매니저 대시보드 (manager/chief 전용)
class ManagerDashboardPage extends ConsumerWidget {
  const ManagerDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    if (user == null || !user.canManageDashboard) {
      return Scaffold(
        appBar: AppBar(title: const Text('권한 없음')),
        body: const Center(child: Text('매니저/실장만 접근 가능합니다.')),
      );
    }

    final unassigned = ref.watch(unassignedCleaningsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('매니저 대시보드', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text('미지정 청소', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            unassigned.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('오류: $e', style: const TextStyle(color: AppColors.danger)),
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text('미지정 청소가 없습니다.', style: TextStyle(color: AppColors.muted))),
                  );
                }
                return Column(
                  children: list.map((c) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.panel,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Row(
                        children: [
                          Container(width: 4, height: 36, decoration: BoxDecoration(color: AppColors.branchColor(c.branchId), borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.branchId, style: const TextStyle(fontWeight: FontWeight.w700)),
                                Text(c.scheduledDate.toString().substring(0, 10), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                              ],
                            ),
                          ),
                          const Text('미지정', style: TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 24),
            const Text('특이사항 / 호점별 점유율 / 사용자 관리는 다음 chunk', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
