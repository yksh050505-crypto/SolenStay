import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/fcm.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';
import '../../main.dart' show kPrefAutoLogin, kPrefThemeMode, themeModeProvider, themeModeToString;
import '../shared/bottom_nav.dart';
import 'package:firebase_messaging/firebase_messaging.dart' show AuthorizationStatus;

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
                SizedBox(height: 10),
                Text(user?.name ?? '...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.branch1.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    roleLabel,
                    style: TextStyle(color: AppColors.branch1, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            SizedBox(height: 22),

            // 매니저/실장 전용
            if (user?.canManageDashboard ?? false) ...[
              _SectionTitle(l.t('관리', 'Management')),
              _menuItem(context,
                emoji: '📊',
                label: l.t('매니저 대시보드', 'Manager dashboard'),
                onTap: () => context.push('/manager'),
              ),
              // 매니저만 — 관리자 설정
              if (user?.isManager ?? false)
                _menuItem(context,
                  emoji: '⚙️',
                  label: l.t('관리자 설정', 'Admin settings'),
                  onTap: () => context.push('/admin/settings'),
                ),
              SizedBox(height: 14),
            ],

            // 계정
            _SectionTitle(l.t('계정', 'Account')),
            _menuItem(context, emoji: '🔒', label: l.t('PIN 변경', 'Change PIN'), onTap: () => _changePinDialog(context, ref)),
            _menuItem(context,
              emoji: '👤',
              label: l.t('이름 / 프로필 사진', 'Name / Profile photo'),
              onTap: user == null ? null : () => _editProfileDialog(context, ref, user),
            ),
            // 자동 로그인 토글 (디바이스별 SharedPreferences에 저장)
            _AutoLoginToggle(l: l),
            SizedBox(height: 14),

            // 알림 — 각 토글이 사용자 prefs(notificationPrefs.{key})에 저장됨
            _SectionTitle(l.t('알림', 'Notifications')),
            // 권한 안 켜져있으면 활성화 카드 표시 (켜져있으면 숨김)
            _NotificationPermissionCard(l: l),
            _toggleItem(context,
              emoji: '🔔',
              label: l.t('새 청소 일정 알림', 'New cleaning alerts'),
              value: user?.prefEnabled(_kPrefNewCleaning) ?? true,
              onChanged: user == null ? null : (v) => _toggleNotifPref(context, ref, _kPrefNewCleaning, v),
            ),
            _toggleItem(context,
              emoji: '📣',
              label: l.t('매니저 공지사항', 'Manager notices'),
              value: user?.prefEnabled(_kPrefManagerNotice) ?? true,
              onChanged: user == null ? null : (v) => _toggleNotifPref(context, ref, _kPrefManagerNotice, v),
            ),
            _toggleItem(context,
              emoji: '📅',
              label: l.t('일정 변경 알림', 'Schedule change alerts'),
              value: user?.prefEnabled(_kPrefScheduleChange) ?? true,
              onChanged: user == null ? null : (v) => _toggleNotifPref(context, ref, _kPrefScheduleChange, v),
            ),
            SizedBox(height: 14),

            // 기타
            _SectionTitle(l.t('기타', 'More')),
            _menuItem(context,
              emoji: '🌓',
              label: l.t('테마', 'Theme'),
              trailing: Consumer(builder: (ctx, ref, _) {
                final mode = ref.watch(themeModeProvider);
                final label = mode == ThemeMode.system
                    ? l.t('시스템', 'System')
                    : mode == ThemeMode.light
                        ? l.t('라이트', 'Light')
                        : l.t('다크', 'Dark');
                return Text('$label ›', style: TextStyle(color: context.brand.muted, fontSize: 13));
              }),
              onTap: () => _themeDialog(context, ref, l),
            ),
            _menuItem(context,
              emoji: '🌐',
              label: l.t('언어', 'Language'),
              trailing: Text(
                '${l.t('한국어', 'English')} ›',
                style: TextStyle(color: context.brand.muted, fontSize: 13),
              ),
              onTap: () => _languageDialog(context, ref, user),
            ),
            _menuItem(context,
              emoji: '📆',
              label: l.t('내 청소 캘린더 연동', 'Sync my cleaning calendar'),
              onTap: () => context.push('/profile/calendar-sync'),
            ),
            _menuItem(context,
              emoji: '❓',
              label: l.t('도움말 / 문의', 'Help / Contact'),
              onTap: () => context.push('/help'),
            ),
            _menuItem(context,
              emoji: 'ℹ️',
              label: l.t('앱 버전', 'App version'),
              trailing: Consumer(builder: (ctx, ref, _) {
                final info = ref.watch(appBuildInfoProvider).valueOrNull;
                final text = info == null ? '...' : 'v${info.version}';
                return Text(text, style: TextStyle(color: context.brand.dim, fontSize: 12));
              }),
              onTap: () => _showAbout(context, ref, l),
            ),
            SizedBox(height: 18),

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
                child: Text(l.t('로그아웃', 'Sign out'), style: TextStyle(fontWeight: FontWeight.w700)),
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
                            child: Padding(
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
                      icon: Icon(Icons.delete_outline, size: 16),
                      style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                      label: Text(l.t('사진 제거', 'Remove photo')),
                    ),
                  SizedBox(height: 8),
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
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(l.t('저장', 'Save')),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 테마 선택 (시스템 / 라이트 / 다크)
  Future<void> _themeDialog(BuildContext context, WidgetRef ref, L10n l) async {
    final current = ref.read(themeModeProvider);
    final picked = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l.t('테마', 'Theme')),
        children: [
          for (final mode in ThemeMode.values)
            RadioListTile<ThemeMode>(
              value: mode,
              groupValue: current,
              title: Text(
                mode == ThemeMode.system
                    ? l.t('시스템', 'System')
                    : mode == ThemeMode.light
                        ? l.t('라이트', 'Light')
                        : l.t('다크', 'Dark'),
              ),
              subtitle: mode == ThemeMode.system
                  ? Text(
                      l.t('휴대폰 설정 따라가기', "Follow phone's setting"),
                      style: TextStyle(fontSize: 11),
                    )
                  : null,
              onChanged: (v) => Navigator.of(ctx).pop(v),
            ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    ref.read(themeModeProvider.notifier).state = picked;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPrefThemeMode, themeModeToString(picked));
    } catch (_) {}
  }

  /// 본인 청소 캘린더 구독 다이얼로그 — 구글/아이폰/URL 복사/재발급/해제
  Future<void> _calendarSyncDialog(BuildContext context, WidgetRef ref, L10n l) async {
    final fn = ref.read(functionsServiceProvider);
    String? token;
    String? error;
    bool busy = true;

    Future<void> load(Future<String> Function() get) async {
      try {
        token = await get();
        error = null;
      } catch (e) {
        error = '$e';
      } finally {
        busy = false;
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        if (busy && token == null && error == null) {
          // 첫 진입 시 토큰 발급
          // ignore: discarded_futures
          load(fn.getOrCreateCalendarToken).then((_) => setLocal(() {}));
        }
        final url = token == null ? null : fn.calendarSubscriptionUrl(token!);
        final webcal = url == null ? null : url.replaceFirst('https://', 'webcal://');
        final googleAdd = url == null
            ? null
            : 'https://calendar.google.com/calendar/render?cid=${Uri.encodeComponent(url)}';

        return AlertDialog(
          title: Text(l.t('내 청소 캘린더 연동', 'Sync my cleaning calendar')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.t(
                    '본인이 배정된 청소만 구글/아이폰 캘린더에 자동으로 반영됩니다.\n등록 후 새 청소가 배정되면 자동으로 추가됩니다.',
                    'Only your assigned cleanings will appear. New assignments sync automatically.',
                  ),
                  style: TextStyle(fontSize: 12, color: context.brand.muted),
                ),
                const SizedBox(height: 14),
                if (busy && url == null)
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                else if (error != null)
                  Text(error!, style: const TextStyle(color: AppColors.danger, fontSize: 12))
                else if (url != null) ...[
                  // 구글 캘린더
                  FilledButton.icon(
                    onPressed: () => launchUrl(Uri.parse(googleAdd!), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.event, size: 16),
                    label: Text(l.t('구글 캘린더에 추가', 'Add to Google Calendar')),
                  ),
                  const SizedBox(height: 8),
                  // 아이폰 캘린더
                  OutlinedButton.icon(
                    onPressed: () => launchUrl(Uri.parse(webcal!), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.phone_iphone, size: 16),
                    label: Text(l.t('아이폰 캘린더에 추가', 'Add to iPhone Calendar')),
                  ),
                  const SizedBox(height: 8),
                  // URL 복사
                  OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.t('구독 URL 복사됨', 'URL copied'))),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(l.t('구독 URL 복사', 'Copy URL')),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.brand.panel2,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      url,
                      style: TextStyle(fontSize: 10, color: context.brand.muted, fontFamily: 'monospace'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            // 좌측: 재발급 / 연동 해제
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setLocal(() { busy = true; token = null; error = null; });
                      await load(fn.regenerateCalendarToken);
                      setLocal(() {});
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.t('새 URL 발급됨 (이전 URL은 무효)', 'New URL issued'))),
                        );
                      }
                    },
              child: Text(l.t('재발급', 'Regenerate')),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setLocal(() => busy = true);
                      try {
                        await fn.revokeCalendarToken();
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l.t('연동 해제됨', 'Sync disabled'))),
                          );
                        }
                      } catch (e) {
                        setLocal(() { busy = false; error = '$e'; });
                      }
                    },
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: Text(l.t('연동 해제', 'Disconnect')),
            ),
            const Spacer(),
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l.t('닫기', 'Close'))),
          ],
        );
      }),
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

  void _showAbout(BuildContext context, WidgetRef ref, L10n l) {
    final info = ref.read(appBuildInfoProvider).valueOrNull;
    final ver = info == null ? '...' : 'v${info.version} (build ${info.buildNumber})';
    showAboutDialog(
      context: context,
      applicationName: 'SolenStay',
      applicationVersion: ver,
      applicationLegalese: l.t('1·2·3호점 예약·청소 관리', 'Reservation & cleaning management'),
    );
  }

  Future<void> _changePinDialog(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('PIN 변경'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(hintText: '새 PIN (6자리 숫자)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text('변경')),
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

  Widget _menuItem(
    BuildContext context, {
    required String emoji,
    required String label,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: context.brand.panel,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.brand.line),
            ),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 10),
                Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.brand.text))),
                trailing ?? Icon(Icons.chevron_right, color: context.brand.muted, size: 18),
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

  Widget _toggleItem(
    BuildContext context, {
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
          color: context.brand.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.brand.line),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: context.brand.text))),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.white,
              activeTrackColor: AppColors.branch1,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: context.brand.line,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

/// 프로필 아바타 — 사진이 있으면 사진, 없으면 이름 첫 글자
/// 알림 권한 카드 — 권한 없을 때만 활성화 버튼 표시.
/// 자동 권한 요청은 안 하고(매번 팝업 뜨는 문제 방지), 사용자가 직접 누를 때만 요청.
class _NotificationPermissionCard extends ConsumerStatefulWidget {
  final L10n l;
  const _NotificationPermissionCard({required this.l});
  @override
  ConsumerState<_NotificationPermissionCard> createState() => _NotificationPermissionCardState();
}

class _NotificationPermissionCardState extends ConsumerState<_NotificationPermissionCard> {
  AuthorizationStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final s = await currentNotificationStatus();
    if (mounted) setState(() => _status = s);
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    final ok = await requestNotificationPermissionExplicit(ref.read(functionsServiceProvider));
    if (!mounted) return;
    await _refresh();
    setState(() => _busy = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.l.t('알림이 켜졌습니다', 'Notifications enabled')), backgroundColor: AppColors.ok),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.l.t('알림 권한이 거부됐어요. 브라우저/폰 설정에서 직접 허용하세요',
            'Permission denied. Please allow in browser/phone settings'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 권한 이미 허용됐으면 카드 자체를 숨김
    if (_status == AuthorizationStatus.authorized) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.warn.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: _busy ? null : _enable,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.warn.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                Text('🔕', style: TextStyle(fontSize: 16)),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.l.t('알림이 꺼져 있습니다', 'Notifications are off'),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.warn),
                      ),
                      SizedBox(height: 2),
                      Text(
                        widget.l.t('탭하여 알림 받기', 'Tap to enable'),
                        style: TextStyle(fontSize: 11, color: context.brand.muted),
                      ),
                    ],
                  ),
                ),
                if (_busy)
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Icon(Icons.chevron_right, color: AppColors.warn, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 디바이스별 자동 로그인 토글 — SharedPreferences에 'auto_login_enabled' 저장.
/// 켜면 앱 시작 시 로그인 유지(자동 진입), 끄면(기본) 매번 PIN 로그인.
class _AutoLoginToggle extends StatefulWidget {
  final L10n l;
  const _AutoLoginToggle({required this.l});
  @override
  State<_AutoLoginToggle> createState() => _AutoLoginToggleState();
}

class _AutoLoginToggleState extends State<_AutoLoginToggle> {
  bool? _value;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => _value = prefs.getBool(kPrefAutoLogin) ?? false);
  }

  Future<void> _set(bool v) async {
    setState(() => _value = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefAutoLogin, v);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(v
              ? widget.l.t('자동 로그인 켜짐 — 다음부터 앱 시작 시 바로 진입',
                  'Auto sign-in ON — opens app directly next time')
              : widget.l.t('자동 로그인 꺼짐 — 앱 시작 시 PIN 로그인 화면',
                  'Auto sign-in OFF — PIN login required on each start')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.brand.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: context.brand.line),
        ),
        child: Row(
          children: [
            Text('🔓', style: TextStyle(fontSize: 16)),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.l.t('자동 로그인 (이 기기)', 'Auto sign-in (this device)'),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 2),
                  Text(
                    widget.l.t('끄면 앱 시작 시마다 PIN 로그인', 'When off, PIN required on each app start'),
                    style: TextStyle(fontSize: 10, color: context.brand.muted),
                  ),
                ],
              ),
            ),
            Switch(
              value: _value ?? false,
              onChanged: _value == null ? null : _set,
              activeColor: Colors.white,
              activeTrackColor: AppColors.branch1,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: context.brand.line,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

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
      decoration: BoxDecoration(color: AppColors.branch1, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: hasPhoto
          ? CachedNetworkImage(
              imageUrl: photoUrl!,
              fit: BoxFit.cover,
              placeholder: (_, __) => Center(
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
        style: TextStyle(
          color: context.brand.muted,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
