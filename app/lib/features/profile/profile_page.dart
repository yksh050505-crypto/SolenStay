import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/services.dart';
import '../shared/bottom_nav.dart';

/// 알림 토글 상태 (로컬 상태)
final _notiNewCleaningProvider = StateProvider<bool>((_) => true);
final _notiManagerProvider = StateProvider<bool>((_) => true);
final _notiScheduleProvider = StateProvider<bool>((_) => false);

/// ⑥ 내정보 (프로필/설정) - 목업 디자인 적용
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final roleLabel = user?.isManager == true
        ? '매니저'
        : user?.isChief == true
            ? '실장'
            : '청소원';

    return Scaffold(
      appBar: AppBar(
        title: const Text('내정보'),
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: const AppBottomNav(active: BottomTab.profile),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          children: [
            // 프로필 (중앙 정렬)
            Column(
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: AppColors.branch1,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      user?.name.isNotEmpty == true ? user!.name[0] : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(user?.name ?? '...', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.branch1.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    roleLabel,
                    style: const TextStyle(color: AppColors.branch1, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),

            // 매니저/실장 전용
            if (user?.canManageDashboard ?? false) ...[
              const _SectionTitle('관리'),
              _menuItem(
                emoji: '📊',
                label: '매니저 대시보드',
                onTap: () => context.push('/manager'),
              ),
              // 매니저만 — 관리자 설정
              if (user?.isManager ?? false)
                _menuItem(
                  emoji: '⚙️',
                  label: '관리자 설정',
                  onTap: () => context.push('/admin/settings'),
                ),
              const SizedBox(height: 14),
            ],

            // 계정
            const _SectionTitle('계정'),
            _menuItem(emoji: '🔒', label: 'PIN 변경', onTap: () => _changePinDialog(context, ref)),
            _menuItem(emoji: '👤', label: '이름 / 프로필 사진', onTap: () => _comingSoon(context)),
            const SizedBox(height: 14),

            // 알림
            const _SectionTitle('알림'),
            _toggleItem(
              emoji: '🔔',
              label: '새 청소 일정 알림',
              value: ref.watch(_notiNewCleaningProvider),
              onChanged: (v) => ref.read(_notiNewCleaningProvider.notifier).state = v,
            ),
            _toggleItem(
              emoji: '📣',
              label: '매니저 공지사항',
              value: ref.watch(_notiManagerProvider),
              onChanged: (v) => ref.read(_notiManagerProvider.notifier).state = v,
            ),
            _toggleItem(
              emoji: '📅',
              label: '일정 변경 알림',
              value: ref.watch(_notiScheduleProvider),
              onChanged: (v) => ref.read(_notiScheduleProvider.notifier).state = v,
            ),
            const SizedBox(height: 14),

            // 기타
            const _SectionTitle('기타'),
            _menuItem(
              emoji: '🌐',
              label: '언어',
              trailing: const Text('한국어 ›', style: TextStyle(color: AppColors.muted, fontSize: 13)),
              onTap: () => _comingSoon(context),
            ),
            _menuItem(emoji: '❓', label: '도움말 / 문의', onTap: () => _comingSoon(context)),
            _menuItem(
              emoji: 'ℹ️',
              label: '앱 버전',
              trailing: const Text('v0.1.0', style: TextStyle(color: AppColors.dim, fontSize: 12)),
              onTap: null,
            ),
            const SizedBox(height: 18),

            // 로그아웃
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(color: AppColors.danger.withOpacity(0.3)),
                  backgroundColor: AppColors.danger.withOpacity(0.04),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                },
                child: const Text('로그아웃', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('곧 지원될 기능입니다'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _changePinDialog(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PIN 변경'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(hintText: '새 PIN (6자리 숫자)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('변경')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    if (result.length != 6) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN은 6자리 숫자여야 합니다')),
        );
      }
      return;
    }
    try {
      await ref.read(functionsServiceProvider).changePin(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN이 변경되었습니다'), backgroundColor: AppColors.ok),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PIN 변경 실패: $e')));
      }
    }
  }

  Widget _menuItem({
    required String emoji,
    required String label,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                trailing ?? const Icon(Icons.chevron_right, color: AppColors.muted, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _toggleItem({
    required String emoji,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.white,
              activeTrackColor: AppColors.branch1,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: AppColors.line,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 6, top: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.muted,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
