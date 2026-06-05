import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';

/// 홈에 마운트되어 한 번만 동작하는 업데이트 체커.
/// - 웹에서는 체크하지 않음 (웹은 항상 최신)
/// - Firestore config/appVersion 의 latestCode > 현재 buildNumber 일 때 다이얼로그
/// - mandatory=true 면 닫기 버튼 없음
class UpdateChecker extends ConsumerStatefulWidget {
  const UpdateChecker({super.key});

  @override
  ConsumerState<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends ConsumerState<UpdateChecker> {
  bool _shown = false;
  int? _currentCode;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      PackageInfo.fromPlatform().then((info) {
        if (!mounted) return;
        setState(() {
          _currentCode = int.tryParse(info.buildNumber) ?? 0;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 웹에서는 동작 X
    if (kIsWeb) return const SizedBox.shrink();
    if (_currentCode == null) return const SizedBox.shrink();

    final asyncVersion = ref.watch(appVersionProvider);
    asyncVersion.whenData((v) {
      if (v == null) return;
      if (v.apkUrl.isEmpty) return;
      if (v.latestCode <= (_currentCode ?? 0)) return;
      if (_shown) return;
      _shown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showUpdateDialog(context, v);
      });
    });
    return const SizedBox.shrink();
  }

  Future<void> _showUpdateDialog(BuildContext context, AppVersionModel v) async {
    final l = L10n.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: !v.mandatory,
      builder: (ctx) {
        return PopScope(
          canPop: !v.mandatory,
          child: AlertDialog(
            title: Row(
              children: [
                Icon(Icons.system_update, color: AppColors.branch1),
                SizedBox(width: 8),
                Expanded(
                  child: Text(l.t('새 버전 업데이트', 'New Version Available')),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l.t('새 버전 ${v.latest} 이(가) 출시되었습니다.',
                        'Version ${v.latest} is now available.'),
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (v.releaseNotes.isNotEmpty) ...[
                    SizedBox(height: 12),
                    Text(
                      l.t('변경 내용', 'Release notes'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.brand.dim,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(v.releaseNotes, style: TextStyle(fontSize: 13)),
                  ],
                  SizedBox(height: 12),
                  Text(
                    l.t(
                      '"지금 업데이트" 를 누르면 브라우저로 APK가 다운로드됩니다.\n다운로드 후 알림에서 파일을 눌러 설치하세요.',
                      'Tap "Update Now" to download the APK in your browser.\nOpen the file from the notification to install.',
                    ),
                    style: TextStyle(fontSize: 12, color: context.brand.dim),
                  ),
                ],
              ),
            ),
            actions: [
              if (!v.mandatory)
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l.t('나중에', 'Later')),
                ),
              FilledButton.icon(
                onPressed: () async {
                  final ok = await _openApkUrl(v.apkUrl);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l.t('링크를 열 수 없습니다', 'Could not open link'))),
                    );
                  }
                  if (!v.mandatory && ctx.mounted) Navigator.of(ctx).pop();
                },
                icon: Icon(Icons.download),
                label: Text(l.t('지금 업데이트', 'Update Now')),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _openApkUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
