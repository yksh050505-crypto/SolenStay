import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';
import '../manager/manager_dashboard_page.dart' show allUsersProvider;
import '../notifications/notifications_page.dart' show NotificationItem, sentNoticesProvider;
import 'apk_picker_stub.dart' if (dart.library.js_interop) 'apk_picker_web.dart';

/// 관리자 설정 (매니저 전용)
/// - 사용자 추가/관리
/// - (추후) 호점 설정, iCal URL 관리, 알림 설정 등
class AdminSettingsPage extends ConsumerWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    if (userAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('관리자 설정'),
          leading: IconButton(icon: Icon(Icons.arrow_back), onPressed: () => context.pop()),
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final user = userAsync.value;
    // 매니저만 접근 (실장은 불가)
    if (user == null || !user.isManager) {
      return Scaffold(
        appBar: AppBar(
          title: Text('권한 없음'),
          leading: IconButton(icon: Icon(Icons.arrow_back), onPressed: () => context.pop()),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 48, color: context.brand.dim),
              SizedBox(height: 12),
              Text('매니저만 접근 가능합니다', style: TextStyle(color: context.brand.muted)),
            ],
          ),
        ),
      );
    }

    final allUsers = ref.watch(allUsersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('관리자 설정'),
        leading: IconButton(icon: Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            // 매니저 공지사항 섹션
            const _SectionHeader(title: '공지사항'),
            SizedBox(height: 10),
            Material(
              color: AppColors.warn.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => _showNoticeDialog(context, ref),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.warn.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.warn.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.campaign_outlined, color: AppColors.warn, size: 20),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('매니저 공지사항 작성', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            SizedBox(height: 2),
                            Text('사용자들에게 알림으로 전달됩니다', style: TextStyle(color: context.brand.muted, fontSize: 11)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: context.brand.dim, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: 14),
            // 보낸 공지 목록
            _SentNoticesSection(),
            SizedBox(height: 24),

            // 달력 일정 관리
            const _SectionHeader(title: '달력 일정'),
            SizedBox(height: 10),
            Material(
              color: AppColors.branch1.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => context.push('/admin/reservations'),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.branch1.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.branch1.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.calendar_month_outlined, color: AppColors.branch1, size: 20),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('예약 일정 추가/수정/삭제', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            SizedBox(height: 2),
                            Text('iCal로 들어온 일정 보정 및 수동 예약 관리', style: TextStyle(color: context.brand.muted, fontSize: 11)),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: context.brand.dim, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: 24),

            // 호점 동기화 (iCal) — 각 호점의 Google Calendar iCal 주소 연결
            const _SectionHeader(title: '호점 동기화 (iCal)'),
            SizedBox(height: 10),
            const _BranchSyncSection(),
            SizedBox(height: 24),

            // 앱 버전 등록 (Android APK 업데이트 알림용)
            const _SectionHeader(title: '앱 버전 (Android)'),
            SizedBox(height: 10),
            const _AppVersionSection(),
            SizedBox(height: 24),

            // 사용자 관리 섹션
            Row(
              children: [
                Expanded(child: _SectionHeader(title: '사용자 관리')),
                TextButton.icon(
                  onPressed: () => _showAddUserDialog(context, ref),
                  icon: Icon(Icons.person_add_alt, size: 16),
                  label: Text('사용자 추가'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.branch1,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    textStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            allUsers.when(
              loading: () => Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('오류: $e', style: TextStyle(color: AppColors.danger)),
              data: (list) {
                if (list.isEmpty) {
                  return _emptyBox('등록된 사용자가 없습니다');
                }
                list.sort((a, b) {
                  int prio(UserModel u) => u.isManager ? 0 : u.isChief ? 1 : 2;
                  final c = prio(a).compareTo(prio(b));
                  return c != 0 ? c : a.name.compareTo(b.name);
                });
                return Column(
                  children: list.map((u) => _UserRow(user: u)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyBox(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.muted.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(text, style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }

  /// 매니저 공지사항 작성 다이얼로그
  Future<void> _showNoticeDialog(BuildContext context, WidgetRef ref) async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    String target = 'all';
    bool loading = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.campaign_outlined, color: AppColors.warn, size: 22),
              SizedBox(width: 8),
              Text('공지사항 작성'),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleCtrl,
                    maxLength: 50,
                    decoration: InputDecoration(
                      labelText: '제목',
                      hintText: '예: 5월 청소 일정 안내',
                    ),
                  ),
                  SizedBox(height: 4),
                  TextField(
                    controller: bodyCtrl,
                    maxLines: 5,
                    maxLength: 500,
                    decoration: InputDecoration(
                      labelText: '내용',
                      hintText: '공지 내용을 입력하세요...',
                      alignLabelWithHint: true,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text('수신 대상', style: TextStyle(fontSize: 11, color: context.brand.muted, fontWeight: FontWeight.w700)),
                  SizedBox(height: 6),
                  // 대상 선택 칩
                  Wrap(
                    spacing: 6,
                    children: [
                      _targetChip('all', '전체', target, (v) => setState(() => target = v)),
                      _targetChip('cleaners', '청소원', target, (v) => setState(() => target = v)),
                      _targetChip('admins', '관리자', target, (v) => setState(() => target = v)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: Text('취소'),
            ),
            FilledButton.icon(
              onPressed: loading
                  ? null
                  : () async {
                      final title = titleCtrl.text.trim();
                      final body = bodyCtrl.text.trim();
                      if (title.isEmpty || body.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('제목과 내용을 입력하세요')),
                        );
                        return;
                      }
                      setState(() => loading = true);
                      try {
                        final result = await ref.read(functionsServiceProvider).createManagerNotice(
                              title: title,
                              body: body,
                              target: target,
                            );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          final count = result['recipientCount'] ?? 0;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('공지 전송 완료 (수신자 $count명)'),
                              backgroundColor: AppColors.ok,
                            ),
                          );
                        }
                      } catch (e) {
                        setState(() => loading = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('전송 실패: $e')));
                        }
                      }
                    },
              icon: loading
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(Icons.send, size: 16),
              label: Text('전송'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.warn),
            ),
          ],
        ),
      ),
    );
  }

  Widget _targetChip(String value, String label, String selected, ValueChanged<String> onTap) {
    final isSelected = value == selected;
    return Material(
      color: isSelected ? AppColors.warn.withOpacity(0.15) : AppColors.panel2,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: () => onTap(value),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: isSelected ? AppColors.warn : AppColors.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? AppColors.warn : AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAddUserDialog(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final pinCtrl = TextEditingController(text: '000000');
    String role = 'cleaner';
    bool loading = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('사용자 추가'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 일괄 추가
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.brand.panel2,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('초기 일괄 추가 (PIN=000000)', style: TextStyle(fontSize: 11, color: context.brand.muted, fontWeight: FontWeight.w700)),
                      SizedBox(height: 6),
                      FilledButton(
                        onPressed: loading
                            ? null
                            : () async {
                                setState(() => loading = true);
                                await _batchAddInitialUsers(context, ref);
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                          minimumSize: const Size(0, 28),
                        ),
                        child: Text('초기 6명 추가'),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '박제인(매니저), 송현주(실장), 에블린·김소영·리첼·조은희(청소원)',
                        style: TextStyle(fontSize: 10, color: context.brand.dim),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 14),
                Text('또는 개별 추가', style: TextStyle(fontSize: 11, color: context.brand.muted, fontWeight: FontWeight.w700)),
                SizedBox(height: 8),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: '이름', hintText: '예: 박제인'),
                ),
                SizedBox(height: 8),
                TextField(
                  controller: pinCtrl,
                  decoration: InputDecoration(labelText: '초기 PIN'),
                  keyboardType: TextInputType.number,
                ),
                SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: InputDecoration(labelText: '역할'),
                  items: const [
                    DropdownMenuItem(value: 'cleaner', child: Text('청소원')),
                    DropdownMenuItem(value: 'chief', child: Text('실장')),
                    DropdownMenuItem(value: 'manager', child: Text('매니저')),
                  ],
                  onChanged: (v) => setState(() => role = v ?? 'cleaner'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: loading ? null : () => Navigator.pop(ctx), child: Text('취소')),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      final pin = pinCtrl.text.trim();
                      if (name.isEmpty || pin.length < 4) return;
                      setState(() => loading = true);
                      try {
                        await ref.read(functionsServiceProvider).registerUser(name: name, pin: pin, role: role);
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$name ($role) 추가됨'), backgroundColor: AppColors.ok),
                          );
                        }
                      } catch (e) {
                        setState(() => loading = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('추가 실패: $e')));
                        }
                      }
                    },
              child: loading
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('추가'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _batchAddInitialUsers(BuildContext context, WidgetRef ref) async {
    final users = [
      ('박제인', 'manager'),
      ('송현주', 'chief'),
      ('에블린', 'cleaner'),
      ('김소영', 'cleaner'),
      ('리첼', 'cleaner'),
      ('조은희', 'cleaner'),
    ];

    final fn = ref.read(functionsServiceProvider);
    int added = 0;
    final errors = <String>[];

    for (final (name, role) in users) {
      try {
        await fn.registerUser(name: name, pin: '000000', role: role);
        added++;
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('already-exists') || msg.contains('already')) {
          // 이미 존재
        } else {
          errors.add('$name: $e');
        }
      }
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errors.isEmpty
              ? '$added명 추가 완료 (이미 있는 사용자는 스킵)'
              : '$added명 추가 / 실패 ${errors.length}건'),
          backgroundColor: errors.isEmpty ? AppColors.ok : null,
        ),
      );
    }
  }
}

/// 호점별 iCal 동기화 주소 관리 — 매니저가 각 호점의 Google Calendar iCal URL을 연결.
/// 앱 버전 등록 섹션 (Android APK 업데이트 알림용)
/// - 현재 등록된 최신 버전 표시
/// - "새 버전 등록" → 다이얼로그 (버전, APK URL, 변경 내용, 필수 여부)
class _AppVersionSection extends ConsumerWidget {
  const _AppVersionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncVer = ref.watch(appVersionProvider);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.brand.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.brand.line),
      ),
      child: asyncVer.when(
        loading: () => SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
        error: (e, _) => Text('불러오기 실패: $e', style: TextStyle(color: AppColors.danger)),
        data: (v) {
          final hasVersion = v != null && v.latest.isNotEmpty;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.branch1.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.system_update, color: AppColors.branch1, size: 20),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasVersion ? '최신 버전: ${v.latest}  (code ${v.latestCode})' : '등록된 버전 없음',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        SizedBox(height: 2),
                        Text(
                          hasVersion && v.mandatory ? '필수 업데이트 ON' : '선택적 업데이트',
                          style: TextStyle(
                            fontSize: 11,
                            color: hasVersion && v.mandatory ? AppColors.danger : context.brand.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (hasVersion && v.releaseNotes.isNotEmpty) ...[
                SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.brand.bg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(v.releaseNotes, style: TextStyle(fontSize: 12, color: context.brand.text)),
                ),
              ],
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _showVersionDialog(context, ref, v),
                      icon: Icon(Icons.upload, size: 16),
                      label: Text('새 버전 등록'),
                    ),
                  ),
                  if (hasVersion) ...[
                    SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () => _confirmUnregister(context, ref),
                      icon: Icon(Icons.delete_outline, size: 16, color: AppColors.danger),
                      label: Text('등록 취소', style: TextStyle(color: AppColors.danger)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.danger),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmUnregister(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('버전 등록 취소'),
        content: Text(
          'Firestore 의 config/appVersion 문서를 삭제합니다.\n'
          '이후 어떤 기기에서도 업데이트 다이얼로그가 더 이상 표시되지 않습니다.\n\n'
          '계속할까요?',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(firestoreProvider).collection('config').doc('appVersion').delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('버전 등록이 취소되었습니다')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('취소 실패: $e')),
        );
      }
    }
  }

  Future<void> _showVersionDialog(BuildContext context, WidgetRef ref, AppVersionModel? current) async {
    final versionCtrl = TextEditingController(text: current?.latest ?? '');
    final codeCtrl = TextEditingController(text: current != null && current.latestCode > 0 ? '${current.latestCode + 1}' : '2');
    final urlCtrl = TextEditingController(text: current?.apkUrl ?? '');
    final notesCtrl = TextEditingController(text: '');
    bool mandatory = current?.mandatory ?? false;
    bool uploading = false;
    double uploadProgress = 0;
    String? uploadFileName;
    String? uploadError;
    final hasExisting = current != null && current.latest.isNotEmpty;

    final ok = await showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        Future<void> pickAndUpload() async {
          setLocal(() {
            uploadError = null;
          });
          try {
            final picked = await pickApkFile();
            if (picked == null) return;
            final bytes = Uint8List.fromList(picked.bytes);
            final ver = versionCtrl.text.trim().isEmpty ? 'unknown' : versionCtrl.text.trim();
            final safeVer = ver.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
            final path = 'apk/SolenStay-$safeVer.apk';

            setLocal(() {
              uploading = true;
              uploadProgress = 0;
              uploadFileName = picked.name;
            });

            final storageRef = FirebaseStorage.instance.ref(path);
            final task = storageRef.putData(
              bytes,
              SettableMetadata(contentType: 'application/vnd.android.package-archive'),
            );
            task.snapshotEvents.listen((snap) {
              if (snap.totalBytes > 0) {
                setLocal(() => uploadProgress = snap.bytesTransferred / snap.totalBytes);
              }
            });
            await task;
            final url = await storageRef.getDownloadURL();
            setLocal(() {
              urlCtrl.text = url;
              uploading = false;
              uploadProgress = 1;
            });
          } catch (e) {
            setLocal(() {
              uploading = false;
              uploadError = '$e';
            });
          }
        }

        return AlertDialog(
          title: Text('새 버전 등록'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: versionCtrl,
                  decoration: InputDecoration(labelText: '버전 (예: 0.2.1)', isDense: true),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: codeCtrl,
                  decoration: InputDecoration(labelText: '버전 코드 (정수, 비교 기준)', isDense: true),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                SizedBox(height: 10),
                // APK 업로드 영역
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.brand.bg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.brand.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.android, size: 18, color: AppColors.branch1),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text('APK 파일',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.brand.muted)),
                          ),
                          TextButton.icon(
                            onPressed: uploading ? null : pickAndUpload,
                            icon: Icon(Icons.upload_file, size: 14),
                            label: Text('파일 선택', style: TextStyle(fontSize: 12)),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                      if (uploading) ...[
                        SizedBox(height: 6),
                        LinearProgressIndicator(value: uploadProgress > 0 ? uploadProgress : null),
                        SizedBox(height: 4),
                        Text(
                          uploadFileName == null
                              ? '${(uploadProgress * 100).toStringAsFixed(0)}%'
                              : '$uploadFileName  ·  ${(uploadProgress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(fontSize: 11, color: context.brand.muted),
                        ),
                      ],
                      if (uploadError != null) ...[
                        SizedBox(height: 4),
                        Text(uploadError!,
                            style: TextStyle(fontSize: 11, color: AppColors.danger)),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: 10),
                TextField(
                  controller: urlCtrl,
                  decoration: InputDecoration(
                    labelText: 'APK 다운로드 URL',
                    isDense: true,
                    hintText: 'https://… (파일 선택하면 자동 채워짐)',
                  ),
                  keyboardType: TextInputType.url,
                  maxLines: 2,
                  minLines: 1,
                ),
                SizedBox(height: 10),
                TextField(
                  controller: notesCtrl,
                  decoration: InputDecoration(labelText: '변경 내용 (선택)', isDense: true),
                  maxLines: 3,
                  minLines: 2,
                ),
                SizedBox(height: 10),
                SwitchListTile.adaptive(
                  value: mandatory,
                  onChanged: (v) => setLocal(() => mandatory = v),
                  title: Text('필수 업데이트', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  subtitle: Text('켜면 다이얼로그 닫기 불가', style: TextStyle(fontSize: 11)),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            Row(
              children: [
                if (hasExisting)
                  TextButton.icon(
                    onPressed: uploading ? null : () => Navigator.of(ctx).pop('delete'),
                    icon: Icon(Icons.delete_outline, size: 16, color: AppColors.danger),
                    label: Text('현재 등록 삭제', style: TextStyle(color: AppColors.danger, fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                Spacer(),
                TextButton(
                  onPressed: uploading ? null : () => Navigator.of(ctx).pop(null),
                  child: Text('취소'),
                ),
                SizedBox(width: 4),
                FilledButton(
                  onPressed: uploading ? null : () => Navigator.of(ctx).pop('save'),
                  child: Text('등록'),
                ),
              ],
            ),
          ],
        );
      }),
    );

    if (ok == null) return;

    if (ok == 'delete') {
      await _confirmUnregister(context, ref);
      return;
    }

    final version = versionCtrl.text.trim();
    final code = int.tryParse(codeCtrl.text.trim()) ?? 0;
    final url = urlCtrl.text.trim();
    if (version.isEmpty || code <= 0 || url.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('버전 / 코드 / URL 은 필수입니다')),
        );
      }
      return;
    }

    try {
      final model = AppVersionModel(
        latest: version,
        latestCode: code,
        apkUrl: url,
        releaseNotes: notesCtrl.text.trim(),
        mandatory: mandatory,
      );
      await ref.read(firestoreProvider).collection('config').doc('appVersion').set(model.toMap());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('버전 $version 등록 완료')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('등록 실패: $e')),
        );
      }
    }
  }
}

class _BranchSyncSection extends ConsumerWidget {
  const _BranchSyncSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchesAsync = ref.watch(branchesProvider);
    return branchesAsync.when(
      loading: () => Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Text('오류: $e', style: TextStyle(color: AppColors.danger, fontSize: 12)),
      data: (branches) {
        if (branches.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: context.brand.panel2, borderRadius: BorderRadius.circular(10)),
            child: Center(child: Text('등록된 호점이 없습니다', style: TextStyle(color: context.brand.muted, fontSize: 12))),
          );
        }
        return Column(children: branches.map((b) => _BranchSyncRow(branch: b)).toList());
      },
    );
  }
}

class _BranchSyncRow extends ConsumerWidget {
  final BranchModel branch;
  const _BranchSyncRow({required this.branch});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasUrl = branch.iCalSourceUrl.isNotEmpty;
    final color = AppColors.branchColor(branch.id);
    final masked = hasUrl
        ? (branch.iCalSourceUrl.length > 48
            ? '${branch.iCalSourceUrl.substring(0, 48)}…'
            : branch.iCalSourceUrl)
        : 'iCal URL 미설정';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.brand.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              SizedBox(width: 8),
              Text(branch.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (hasUrl ? AppColors.ok : AppColors.warn).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  hasUrl ? '연결됨' : '미연결',
                  style: TextStyle(color: hasUrl ? AppColors.ok : AppColors.warn, fontSize: 10, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            masked,
            style: TextStyle(color: context.brand.muted, fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _editDialog(context, ref),
                icon: Icon(Icons.link, size: 14),
                label: Text('iCal URL 편집'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.branch1,
                  side: BorderSide(color: AppColors.branch1, width: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              SizedBox(width: 8),
              TextButton.icon(
                onPressed: hasUrl ? () => _syncNow(context, ref) : null,
                icon: Icon(Icons.sync, size: 14),
                label: Text('지금 동기화'),
                style: TextButton.styleFrom(
                  foregroundColor: context.brand.muted,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editDialog(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: branch.iCalSourceUrl);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${branch.name} iCal URL'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Google Calendar의 "iCal 형식의 비공개 주소"(…/basic.ics)를 붙여넣으세요.',
                style: TextStyle(fontSize: 12, color: context.brand.muted),
              ),
              SizedBox(height: 10),
              TextField(
                controller: ctrl,
                minLines: 2,
                maxLines: 4,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: 'https://calendar.google.com/calendar/ical/.../basic.ics',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('저장')),
        ],
      ),
    );
    if (saved != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('branches')
          .doc(branch.id)
          .update({'iCalSourceUrl': ctrl.text.trim()});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${branch.name} iCal URL 저장됨'), backgroundColor: AppColors.ok),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
    }
  }

  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${branch.name} 동기화 중...'), duration: const Duration(seconds: 1)),
    );
    try {
      final res = await ref.read(functionsServiceProvider).syncICalManual(branchId: branch.id);
      final r = res[branch.id];
      final msg = r is Map
          ? '추가 ${r['added'] ?? 0} / 갱신 ${r['updated'] ?? 0} / 삭제 ${r['removed'] ?? 0} / 전체 ${r['total'] ?? 0}'
          : '완료';
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${branch.name} 동기화: $msg'), backgroundColor: AppColors.ok),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('동기화 실패: $e')));
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        color: context.brand.muted,
        fontWeight: FontWeight.w700,
        fontSize: 12,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// 보낸 공지 목록 섹션 (펼침 가능)
class _SentNoticesSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_SentNoticesSection> createState() => _SentNoticesSectionState();
}

class _SentNoticesSectionState extends ConsumerState<_SentNoticesSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final sentAsync = ref.watch(sentNoticesProvider);
    final list = sentAsync.valueOrNull ?? const <NotificationItem>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: context.brand.panel,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.brand.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.history, size: 18, color: context.brand.muted),
                  SizedBox(width: 8),
                  Text('보낸 공지', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: context.brand.muted.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${list.length}',
                      style: TextStyle(color: context.brand.muted, fontSize: 10, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: context.brand.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_expanded) ...[
          SizedBox(height: 6),
          sentAsync.when(
            loading: () => Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(12),
              child: Text('오류: $e', style: TextStyle(color: AppColors.danger, fontSize: 12)),
            ),
            data: (l) {
              if (l.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.brand.panel2,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text('아직 보낸 공지가 없습니다', style: TextStyle(color: context.brand.muted, fontSize: 12)),
                  ),
                );
              }
              return Column(
                children: l.map((n) => _SentNoticeCard(notice: n)).toList(),
              );
            },
          ),
        ],
      ],
    );
  }
}

class _SentNoticeCard extends ConsumerWidget {
  final NotificationItem notice;
  const _SentNoticeCard({required this.notice});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.brand.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(notice.title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              Text(
                DateFormat('M/d HH:mm', 'ko').format(notice.createdAt),
                style: TextStyle(color: context.brand.dim, fontSize: 10),
              ),
            ],
          ),
          SizedBox(height: 4),
          Text(
            notice.body,
            style: TextStyle(color: context.brand.muted, fontSize: 12, height: 1.4),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: 8),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.brand.muted.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '읽음 ${notice.readByUids.length}',
                  style: TextStyle(color: context.brand.muted, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
              Spacer(),
              TextButton.icon(
                onPressed: () => _editNotice(context, ref),
                icon: Icon(Icons.edit_outlined, size: 14),
                label: Text('수정'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.branch1,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(width: 4),
              TextButton.icon(
                onPressed: () => _deleteNotice(context, ref),
                icon: Icon(Icons.delete_outline, size: 14),
                label: Text('삭제'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editNotice(BuildContext context, WidgetRef ref) async {
    final titleCtrl = TextEditingController(text: notice.title);
    final bodyCtrl = TextEditingController(text: notice.body);
    bool loading = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text('공지 수정'),
          content: SizedBox(
            width: 360,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: titleCtrl, maxLength: 50, decoration: InputDecoration(labelText: '제목')),
                  SizedBox(height: 4),
                  TextField(
                    controller: bodyCtrl,
                    maxLines: 5,
                    maxLength: 500,
                    decoration: InputDecoration(labelText: '내용', alignLabelWithHint: true),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: loading ? null : () => Navigator.pop(ctx), child: Text('취소')),
            FilledButton(
              onPressed: loading
                  ? null
                  : () async {
                      setState(() => loading = true);
                      try {
                        await ref.read(functionsServiceProvider).updateManagerNotice(
                              notificationId: notice.id,
                              title: titleCtrl.text.trim(),
                              body: bodyCtrl.text.trim(),
                            );
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('공지가 수정되었습니다'), backgroundColor: AppColors.ok),
                          );
                        }
                      } catch (e) {
                        setState(() => loading = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('수정 실패: $e')));
                        }
                      }
                    },
              child: loading
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('저장'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteNotice(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('공지 삭제'),
        content: Text('"${notice.title}" 공지를 삭제하시겠습니까?\n수신자의 알림 목록에서도 사라집니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ref.read(functionsServiceProvider).deleteManagerNotice(notice.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('공지가 삭제되었습니다'), backgroundColor: AppColors.ok),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    }
  }
}

class _UserRow extends ConsumerWidget {
  final UserModel user;
  const _UserRow({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roleLabel = user.isManager
        ? '매니저'
        : user.isChief
            ? '실장'
            : '청소원';
    final roleColor = user.isManager
        ? AppColors.danger
        : user.isChief
            ? AppColors.warn
            : AppColors.branch1;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.brand.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.brand.line),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: roleColor, shape: BoxShape.circle),
            child: Center(
              child: Text(
                user.name.isNotEmpty ? user.name[0] : '?',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    roleLabel,
                    style: TextStyle(color: roleColor, fontSize: 10, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          // PIN 초기화 버튼
          OutlinedButton.icon(
            onPressed: () => _showResetPinDialog(context, ref),
            icon: Icon(Icons.lock_reset, size: 14),
            label: Text('PIN 초기화'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.warn,
              side: BorderSide(color: AppColors.warn, width: 1),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              textStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          // 삭제 버튼 (본인 계정은 숨김)
          if (ref.watch(currentUserProvider).valueOrNull?.uid != user.uid) ...[
            SizedBox(width: 4),
            IconButton(
              onPressed: () => _showDeleteUserDialog(context, ref),
              icon: Icon(Icons.delete_outline, size: 18),
              color: AppColors.danger,
              tooltip: '사용자 삭제',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
          ],
          SizedBox(width: 8),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: user.active ? AppColors.ok : context.brand.dim,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDeleteUserDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('사용자 삭제'),
        content: Text(
          '${user.name} 님을 완전히 삭제하시겠습니까?\n'
          '계정과 모든 정보가 영구 삭제되며 복구할 수 없습니다.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(functionsServiceProvider).deleteUser(user.uid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.name} 님이 삭제되었습니다'), backgroundColor: AppColors.ok),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('삭제 실패: $e')));
      }
    }
  }

  Future<void> _showResetPinDialog(BuildContext context, WidgetRef ref) async {
    final pinCtrl = TextEditingController(text: '000000');
    final newPin = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${user.name} PIN 초기화'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('새 PIN을 입력하세요 (4~8자리).\n사용자가 다음 로그인 시 변경하도록 안내해주세요.',
                style: TextStyle(fontSize: 12, color: context.brand.muted)),
            SizedBox(height: 10),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 8,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: '새 PIN'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, pinCtrl.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.warn),
            child: Text('초기화'),
          ),
        ],
      ),
    );
    if (newPin == null || newPin.isEmpty) return;
    if (newPin.length < 4 || newPin.length > 8) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN은 4~8자리 숫자여야 합니다')),
        );
      }
      return;
    }
    try {
      await ref.read(functionsServiceProvider).updateUserPin(uid: user.uid, pin: newPin);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.name} PIN이 $newPin 으로 초기화되었습니다'), backgroundColor: AppColors.ok),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('초기화 실패: $e')));
      }
    }
  }
}
