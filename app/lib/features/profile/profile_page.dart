import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';
import '../shared/bottom_nav.dart';

/// 알림 prefs 키 — 백엔드와 동일하게 유지
const _kPrefNewCleaning = 'newCleaning';
const _kPrefManagerNotice = 'managerNotice';
const _kPrefScheduleChange = 'scheduleChange';

/// ⑥ 내정보 (프로필/설정) - 목업 디자인 적용
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider).value;
    final l = L10n.of(context);
    final roleLabel = user?.isManager == true
        ? l.t('매니저', 'Manager')
        : user?.isChief == true
            ? l.t('실장', 'Chief')
            : l.t('청소원', 'Cleaner');

    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('내정보', 'My Info')),
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
                GestureDetector(
                  onTap: user == null ? null : () => _editProfileDialog(context, ref, user),
                  child: _Avatar(name: user?.name ?? '', photoUrl: user?.photoUrl),
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
              _SectionTitle(l.t('관리', 'Management')),
              _menuItem(
                emoji: '📊',
                label: l.t('매니저 대시보드', 'Manager dashboard'),
                onTap: () => context.push('/manager'),
              ),
              // 매니저만 — 관리자 설정
              if (user?.isManager ?? false)
                _menuItem(
                  emoji: '⚙️',
                  label: l.t('관리자 설정', 'Admin settings'),
                  onTap: () => context.push('/admin/settings'),
                ),
              const SizedBox(height: 14),
            ],

            // 계정
            _SectionTitle(l.t('계정', 'Account')),
            _menuItem(emoji: '🔒', label: l.t('PIN 변경', 'Change PIN'), onTap: () => _changePinDialog(context, ref)),
            _menuItem(
              emoji: '👤',
              label: l.t('이름 / 프로필 사진', 'Name / Profile photo'),
              onTap: user == null ? null : () => _editProfileDialog(context, ref, user),
            ),
            const SizedBox(height: 14),

            // 알림 — 각 토글이 사용자 prefs(notificationPrefs.{key})에 저장됨
            _SectionTitle(l.t('알림', 'Notifications')),
            _toggleItem(
              emoji: '🔔',
              label: l.t('새 청소 일정 알림', 'New cleaning alerts'),
              value: user?.prefEnabled(_kPrefNewCleaning) ?? true,
              onChanged: user == null ? null : (v) => _toggleNotifPref(context, ref, _kPrefNewCleaning, v),
            ),
            _toggleItem(
              emoji: '📣',
              label: l.t('매니저 공지사항', 'Manager notices'),
              value: user?.prefEnabled(_kPrefManagerNotice) ?? true,
              onChanged: user == null ? null : (v) => _toggleNotifPref(context, ref, _kPrefManagerNotice, v),
            ),
            _toggleItem(
              emoji: '📅',
              label: l.t('일정 변경 알림', 'Schedule change alerts'),
              value: user?.prefEnabled(_kPrefScheduleChange) ?? true,
              onChanged: user == null ? null : (v) => _toggleNotifPref(context, ref, _kPrefScheduleChange, v),
            ),
            const SizedBox(height: 14),

            // 기타
            _SectionTitle(l.t('기타', 'More')),
            _menuItem(
              emoji: '🌐',
              label: l.t('언어', 'Language'),
              trailing: Text(
                '${l.t('한국어', 'English')} ›',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              onTap: () => _languageDialog(context, ref, user),
            ),
            _menuItem(
              emoji: '❓',
              label: l.t('도움말 / 문의', 'Help / Contact'),
              onTap: () => context.push('/help'),
            ),
            _menuItem(
              emoji: 'ℹ️',
              label: l.t('앱 버전', 'App version'),
              trailing: const Text('v${AppConstants.appVersion}', style: TextStyle(color: AppColors.dim, fontSize: 12)),
              onTap: () => _showAbout(context, l),
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
                child: Text(l.t('로그아웃', 'Sign out'), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 이름 / 프로필 사진 편집
  Future<void> _editProfileDialog(BuildContext context, WidgetRef ref, UserModel user) async {
    final l = L10n.of(context);
    final nameCtrl = TextEditingController(text: user.name);
    String? pickedPhotoUrl = user.photoUrl;
    bool removePhoto = false;
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> pick() async {
            final picker = ImagePicker();
            final file = await picker.pickImage(
              source: ImageSource.gallery,
              maxWidth: 800,
              maxHeight: 800,
              imageQuality: 80,
            );
            if (file == null) return;
            setState(() => busy = true);
            try {
              final bytes = await file.readAsBytes();
              final ext = file.name.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
              final url = await uploadProfilePhoto(uid: user.uid, bytes: bytes, ext: ext);
              setState(() {
                pickedPhotoUrl = url;
                removePhoto = false;
              });
            } catch (e) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('${l.t('사진 업로드 실패', 'Photo upload failed')}: $e')));
              }
            } finally {
              setState(() => busy = false);
            }
          }

          final showUrl = removePhoto ? null : pickedPhotoUrl;
          return AlertDialog(
            title: Text(l.t('이름 / 프로필 사진', 'Name / Profile photo')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      _Avatar(name: nameCtrl.text, photoUrl: showUrl, size: 84),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Material(
                          color: AppColors.branch1,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: busy ? null : pick,
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.camera_alt, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (showUrl != null)
                    TextButton.icon(
                      onPressed: busy ? null : () => setState(() => removePhoto = true),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                      label: Text(l.t('사진 제거', 'Remove photo')),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(labelText: l.t('이름', 'Name')),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: busy ? null : () => Navigator.pop(ctx), child: Text(l.t('취소', 'Cancel'))),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(l.t('이름을 입력하세요', 'Enter a name'))));
                          return;
                        }
                        setState(() => busy = true);
                        try {
                          await ref.read(functionsServiceProvider).updateMyProfile(
                                name: name == user.name ? null : name,
                                photoUrl: removePhoto ? null : (pickedPhotoUrl != user.photoUrl ? pickedPhotoUrl : null),
                                clearPhoto: removePhoto,
                              );
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(l.t('프로필이 저장되었습니다', 'Profile saved')), backgroundColor: AppColors.ok),
                            );
                          }
                        } catch (e) {
                          setState(() => busy = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('${l.t('저장 실패', 'Save failed')}: $e')));
                          }
                        }
                      },
                child: busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(l.t('저장', 'Save')),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 언어 선택
  Future<void> _languageDialog(BuildContext context, WidgetRef ref, UserModel? user) async {
    final l = L10n.of(context);
    final current = ref.read(localeProvider).languageCode;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.t('언어', 'Language')),
        children: [
          for (final entry in const [('ko', '한국어'), ('en', 'English')])
            RadioListTile<String>(
              value: entry.$1,
              groupValue: current,
              title: Text(entry.$2),
              onChanged: (v) => Navigator.pop(ctx, v),
            ),
        ],
      ),
    );
    if (picked == null || picked == current) return;

    // 즉시 반영 (오버라이드) 후 서버 동기화
    ref.read(localeOverrideProvider.notifier).state = Locale(picked);
    if (user != null) {
      try {
        await ref.read(functionsServiceProvider).updateMyProfile(language: picked);
      } catch (_) {
        // 서버 저장 실패해도 이번 세션 표시는 유지
      }
    }
  }

  void _showAbout(BuildContext context, L10n l) {
    showAboutDialog(
      context: context,
      applicationName: 'SolenStay',
      applicationVersion: 'v${AppConstants.appVersion}',
      applicationLegalese: l.t('1·2·3호점 예약·청소 관리', 'Reservation & cleaning management'),
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

  /// 알림 prefs 한 항목 토글 → 백엔드 저장.
  /// currentUserProvider가 자동 갱신되므로 UI는 별도 setState 불필요.
  Future<void> _toggleNotifPref(BuildContext context, WidgetRef ref, String key, bool value) async {
    try {
      await ref.read(functionsServiceProvider).updateMyProfile(
            notificationPrefs: {key: value},
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('설정 저장 실패: $e')));
      }
    }
  }

  Widget _toggleItem({
    required String emoji,
    required String label,
    required bool value,
    required ValueChanged<bool>? onChanged,
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

/// 프로필 아바타 — 사진이 있으면 사진, 없으면 이름 첫 글자
class _Avatar extends StatelessWidget {
  final String name;
  final String? photoUrl;
  final double size;
  const _Avatar({required this.name, this.photoUrl, this.size = 80});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: AppColors.branch1, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? CachedNetworkImage(
              imageUrl: photoUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => const Center(
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
              ),
              errorWidget: (_, __, ___) => _initial(),
            )
          : _initial(),
    );
  }

  Widget _initial() => Center(
        child: Text(
          name.isNotEmpty ? name[0] : '?',
          style: TextStyle(color: Colors.white, fontSize: size * 0.38, fontWeight: FontWeight.w800),
        ),
      );
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
