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
      height: 68,
      decoration: BoxDecoration(
        color: context.brand.panel,
        border: Border(top: BorderSide(color: context.brand.line)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.10),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _NavItem(
              icon: Icons.home_rounded,
              iconOutlined: Icons.home_outlined,
              label: '홈',
              active: active == BottomTab.home,
              onTap: () => _go(context, BottomTab.home),
            ),
            _NavItem(
              icon: Icons.calendar_today_rounded,
              iconOutlined: Icons.calendar_today_outlined,
              label: '일정',
              active: active == BottomTab.calendar,
              onTap: () => _go(context, BottomTab.calendar),
            ),
            _NavItem(
              icon: Icons.person_rounded,
              iconOutlined: Icons.person_outline,
              label: '내정보',
              active: active == BottomTab.profile,
              onTap: () => _go(context, BottomTab.profile),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData iconOutlined;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({
    required this.icon,
    required this.iconOutlined,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.branch1 : context.brand.dim;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(active ? icon : iconOutlined, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
