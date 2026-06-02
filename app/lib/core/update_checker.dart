import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/services.dart';
import 'theme.dart';

/// 로그인 후 화면에 삽입되어, 등록된 최신 앱 버전(config/appVersion)과
/// 로컬 buildNumber를 비교해 업데이트 안내 다이얼로그를 띄운다.
/// 화면에는 아무것도 그리지 않는다(SizedBox).
///
/// - 웹은 자동 갱신되므로 비활성(kIsWeb).
/// - remote.versionCode > local.buildNumber 이고 apkUrl이 있으면 안내.
/// - forceUpdate=true면 '나중에' 숨기고 닫기 불가.
class UpdateChecker extends ConsumerStatefulWidget {
  const UpdateChecker({super.key});

  @override
  ConsumerState<UpdateChecker> createState() => _UpdateCheckerState();
}

class _UpdateCheckerState extends ConsumerState<UpdateChecker> {
  int? _localCode;
  bool _prompted = false;

  @override
  void initState() {
    super.initState();
    _loadLocalVersion();
  }

  Future<void> _loadLocalVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final code = int.tryParse(info.buildNumber);
      if (mounted) setState(() => _localCode = code);
    } catch (_) {
      // 버전 정보를 못 읽으면 안내 생략
    }
  }

  void _maybePrompt(Map<String, dynamic>? cfg) {
    if (_prompted || _localCode == null || cfg == null) return;
    final remote = (cfg['versionCode'] as num?)?.toInt();
    final url = (cfg['apkUrl'] as String?)?.trim();
    final name = cfg['versionName'] as String? ?? '';
    final force = cfg['forceUpdate'] as bool? ?? false;
    if (remote == null || url == null || url.isEmpty) return;
    if (remote <= _localCode!) return;

    _prompted = true; // 한 번만 안내
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showDialog(name, url, force);
    });
  }

  Future<void> _showDialog(String name, String url, bool force) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: !force,
      builder: (ctx) => PopScope(
        canPop: !force,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.system_update, color: AppColors.branch1, size: 22),
              SizedBox(width: 8),
              Text('업데이트 안내'),
            ],
          ),
          content: Text(
            '새 버전${name.isNotEmpty ? ' v$name' : ''}이(가) 출시되었습니다.\n'
            '${force ? '계속 사용하려면 업데이트가 필요합니다.' : '원활한 사용을 위해 업데이트를 권장합니다.'}',
            style: const TextStyle(height: 1.5),
          ),
          actions: [
            if (!force)
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('나중에'),
              ),
            FilledButton.icon(
              onPressed: () => _download(ctx, url),
              icon: const Icon(Icons.download, size: 18),
              label: const Text('다운로드'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _download(BuildContext dialogCtx, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && dialogCtx.mounted) {
      ScaffoldMessenger.of(dialogCtx).showSnackBar(
        const SnackBar(content: Text('다운로드 링크를 열 수 없습니다')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      final cfg = ref.watch(appVersionConfigProvider).valueOrNull;
      _maybePrompt(cfg);
    }
    return const SizedBox.shrink();
  }
}
