import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';

enum BottomTab { home, calendar, profile }

class AppBottomNav extends StatelessWidget {
  final BottomTab active;
  const AppBottomNav({super.key, required this.active});

  void _go(BuildContext context, BottomTab tab) {
    switch (tab) {
      case BottomTab.home:
        context.go('/home');
        break;
      case BottomTab.calendar:
        context.go('/calendar');
        break;
      case BottomTab.profile:
        context.go('/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: AppColors.bg,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          _NavItem(icon: Icons.home_outlined, label: '홈', active: active == BottomTab.home, onTap: () => _go(context, BottomTab.home)),
          _NavItem(icon: Icons.calendar_today_outlined, label: '일정', active: active == BottomTab.calendar, onTap: () => _go(context, BottomTab.calendar)),
          _NavItem(icon: Icons.person_outline, label: '내정보', active: active == BottomTab.profile, onTap: () => _go(context, BottomTab.profile)),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.branch1 : AppColors.muted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
