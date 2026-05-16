import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../shared/bottom_nav.dart';

/// ③ 작업 상세 (체크리스트) — TODO: 실제 데이터 연결 + 체크리스트 + "다음" 버튼
class CleaningDetailPage extends ConsumerWidget {
  final String cleaningId;
  const CleaningDetailPage({super.key, required this.cleaningId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('청소 작업', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      bottomNavigationBar: const AppBottomNav(active: BottomTab.home),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cleaning_services, size: 64, color: AppColors.muted),
            const SizedBox(height: 12),
            Text('Cleaning $cleaningId', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('체크리스트 화면 — 다음 chunk에서 구현', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => context.push('/cleaning/$cleaningId/complete'),
              child: const Text('다음 (완료 보고로)'),
            ),
          ],
        ),
      ),
    );
  }
}
