import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/theme.dart';
import '../../data/services.dart';
import '../shared/bottom_nav.dart';

/// ⑥ 내정보 (프로필/설정) — PIN 변경, 로그아웃
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('내정보', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        automaticallyImplyLeading: false,
      ),
      bottomNavigationBar: const AppBottomNav(active: BottomTab.profile),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            // 프로필
            Column(
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: const BoxDecoration(color: AppColors.branch1, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      user?.name.isNotEmpty == true ? user!.name[0] : '?',
                      style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(user?.name ?? '...', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 24),
            const _SectionTitle('계정'),
            _menuItem(context, '🔒 PIN 변경', onTap: () => _changePinDialog(context, ref)),
            const SizedBox(height: 14),
            const _SectionTitle('기타'),
            _menuItem(context, '❓ 도움말 / 문의', onTap: () {}),
            _menuItem(context, 'ℹ 앱 버전 v0.1.0', onTap: null, trailing: const SizedBox.shrink()),
            const SizedBox(height: 14),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: Color(0x4DDC2626)),
                backgroundColor: const Color(0x0DDC2626),
              ),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
              },
              child: const Text('로그아웃'),
            ),
          ],
        ),
      ),
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
          maxLength: 8,
          decoration: const InputDecoration(hintText: '새 PIN (4-8자리 숫자)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('변경')),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    try {
      await ref.read(functionsServiceProvider).changePin(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN 변경 완료')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PIN 변경 실패: $e')));
      }
    }
  }

  Widget _menuItem(BuildContext context, String label, {VoidCallback? onTap, Widget? trailing}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
            trailing ?? const Icon(Icons.chevron_right, color: AppColors.muted, size: 18),
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text, style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}
