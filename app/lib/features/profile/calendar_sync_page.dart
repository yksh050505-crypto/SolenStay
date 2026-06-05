import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/services.dart';

/// 내정보 → 청소 캘린더 연동 화면.
/// 본인이 배정된 청소만 구글/아이폰 캘린더에 자동 동기화.
class CalendarSyncPage extends ConsumerStatefulWidget {
  const CalendarSyncPage({super.key});

  @override
  ConsumerState<CalendarSyncPage> createState() => _CalendarSyncPageState();
}

class _CalendarSyncPageState extends ConsumerState<CalendarSyncPage> {
  String? _token;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load(() => ref.read(functionsServiceProvider).getOrCreateCalendarToken());
  }

  Future<void> _load(Future<String> Function() get) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final t = await get();
      if (!mounted) return;
      setState(() {
        _token = t;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  Future<void> _disconnect(L10n l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.t('URL 연결 끊기', 'Disconnect')),
        content: Text(l.t(
          '연결을 끊으면 등록된 캘린더에서 일정이 사라집니다.\n다시 연결하려면 새 URL이 필요합니다.',
          'Existing subscribers will stop receiving updates. A new URL will be required to reconnect.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.t('취소', 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.t('연결 끊기', 'Disconnect')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(functionsServiceProvider).revokeCalendarToken();
      if (!mounted) return;
      setState(() {
        _token = null;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.t('연결이 끊겼습니다', 'Disconnected'))),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _regenerate(L10n l) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.t('URL 재발급', 'Regenerate URL')),
        content: Text(l.t(
          '새 URL을 발급합니다.\n이전 URL은 즉시 무효화되며 등록된 캘린더에 새로 추가해야 합니다.',
          'A new URL will be issued. The old one will stop working immediately.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.t('취소', 'Cancel'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.t('재발급', 'Regenerate')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _load(() => ref.read(functionsServiceProvider).regenerateCalendarToken());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.t('새 URL이 발급되었습니다', 'New URL issued'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final user = ref.watch(currentUserProvider).valueOrNull;
    final fn = ref.read(functionsServiceProvider);
    final url = _token == null ? null : fn.calendarSubscriptionUrl(_token!);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l.t('일정 내보내기', 'Export schedule'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            if (user != null)
              Text(user.name, style: TextStyle(fontSize: 11, color: context.brand.dim, fontWeight: FontWeight.w400)),
          ],
        ),
        centerTitle: false,
        titleSpacing: 0,
      ),
      body: SafeArea(
        child: _busy && _token == null
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        l.t('URL을 불러올 수 없습니다.\n$_error', 'Failed to load URL.\n$_error'),
                        style: const TextStyle(color: AppColors.danger),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 안내 헤더
                        Text(
                          l.t('아래 URL을 복사하여\n원하는 곳에서 일정을 받아보세요.',
                              'Copy the URL below to subscribe in your calendar app.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: context.brand.text,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // URL 박스
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                          decoration: BoxDecoration(
                            color: context.brand.panel2,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: SelectableText(
                              url ?? '',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: context.brand.muted,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),

                        // "URL 복사하기" 큰 버튼
                        SizedBox(
                          height: 54,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.ok,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: url == null
                                ? null
                                : () async {
                                    await Clipboard.setData(ClipboardData(text: url));
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(l.t('URL이 복사되었습니다', 'URL copied'))),
                                    );
                                  },
                            child: Text(
                              l.t('URL 복사하기', 'Copy URL'),
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 연결 끊기 / 재발급 — 작은 텍스트 액션
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 6,
                          children: [
                            Text(
                              l.t('일정 내보내기를 중지하려면', 'To stop exporting'),
                              style: TextStyle(fontSize: 12, color: context.brand.muted),
                            ),
                            InkWell(
                              onTap: _busy ? null : () => _disconnect(l),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    l.t('URL 연결 끊기', 'Disconnect'),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.danger,
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, size: 14, color: AppColors.danger),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton.icon(
                            onPressed: _busy ? null : () => _regenerate(l),
                            icon: Icon(Icons.refresh, size: 14, color: context.brand.muted),
                            label: Text(
                              l.t('URL 재발급', 'Regenerate URL'),
                              style: TextStyle(fontSize: 12, color: context.brand.muted),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // 안내 — PC / 아이폰
                        _GuideBlock(
                          title: l.t('PC에서 구글 캘린더에 추가하려면', 'Add to Google Calendar (PC)'),
                          body: l.t(
                            '구글 캘린더 좌측 "다른 캘린더" 옆의 + 버튼 → "URL로 구독" → 위 URL 붙여넣기',
                            'Google Calendar → "+" next to Other calendars → "From URL" → paste the URL above.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        _GuideBlock(
                          title: l.t('아이폰 캘린더에 추가하려면', 'Add to iPhone Calendar'),
                          body: l.t(
                            '설정 → 캘린더 → 계정 → 계정 추가 → 기타 → 캘린더 구독 추가 → 위 URL 붙여넣기',
                            'Settings → Calendar → Accounts → Add Account → Other → Add Subscribed Calendar → paste URL.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        _GuideBlock(
                          title: l.t('자동 동기화 안내', 'Auto-sync info'),
                          body: l.t(
                            '본인이 배정된 청소만 포함됩니다. 새 청소가 배정되면 자동으로 추가되고, 해제되면 자동으로 사라집니다. (구글: 약 24시간, 아이폰: 약 1시간 단위)',
                            'Only your assigned cleanings are included. New assignments appear automatically (Google ~24h, iPhone ~1h).',
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _GuideBlock extends StatelessWidget {
  final String title;
  final String body;
  const _GuideBlock({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.brand.text),
        ),
        const SizedBox(height: 4),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: context.brand.muted, height: 1.5),
        ),
      ],
    );
  }
}
