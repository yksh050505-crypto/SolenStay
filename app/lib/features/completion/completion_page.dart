import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../shared/bottom_nav.dart';

/// ④ 완료 보고 (사진+메모) — TODO: 사진 첨부 + 메모 + 완료 처리하기 버튼
class CompletionPage extends ConsumerWidget {
  final String cleaningId;
  const CompletionPage({super.key, required this.cleaningId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('완료 보고', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      bottomNavigationBar: const AppBottomNav(active: BottomTab.home),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.task_alt, size: 64, color: AppColors.muted),
            SizedBox(height: 12),
            Text('완료 보고', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            SizedBox(height: 4),
            Text('사진 첨부 + 메모 — 다음 chunk', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
