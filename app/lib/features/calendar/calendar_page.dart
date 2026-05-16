import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../shared/bottom_nav.dart';

/// ⑤ 캘린더 — TODO: table_calendar 위젯으로 호점별 색상 표시
class CalendarPage extends ConsumerWidget {
  const CalendarPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('일정', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: const AppBottomNav(active: BottomTab.calendar),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_month, size: 64, color: AppColors.muted),
            SizedBox(height: 12),
            Text('캘린더 화면 — 다음 chunk에서 table_calendar 적용', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
