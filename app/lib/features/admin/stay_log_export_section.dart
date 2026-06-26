import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';
import 'hwpx_builder.dart';
import 'file_download_stub.dart' if (dart.library.js_interop) 'file_download_web.dart';

/// 숙박일지(.hwpx) 내보내기 섹션 — 관리자 설정 전용.
/// 월·지점을 골라 연번/날짜/성명/숙박일수/수령요금 표를 한글(HWPX)로 받는다.
/// 수령요금은 예약 데이터에 없으므로 빈칸으로 출력(수기 작성).
class StayLogExportSection extends ConsumerWidget {
  const StayLogExportSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: AppColors.ok.withOpacity(0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => _openDialog(context, ref),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.ok.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              Icon(Icons.description_outlined, color: AppColors.ok, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('숙박일지 내보내기',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: context.brand.text)),
                    const SizedBox(height: 2),
                    Text('월·지점 선택 → 한글파일(.hwpx)',
                        style: TextStyle(color: context.brand.muted, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: context.brand.dim, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDialog(BuildContext context, WidgetRef ref) async {
    final branches = ref.read(branchesProvider).valueOrNull ?? const <BranchModel>[];
    if (branches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('호점 정보를 불러오지 못했습니다')),
      );
      return;
    }

    final now = DateTime.now();
    DateTime month = DateTime(now.year, now.month);
    final selected = {for (final b in branches) b.id}; // 기본: 전체 선택
    bool busy = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          void shiftMonth(int delta) {
            setState(() => month = DateTime(month.year, month.month + delta));
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.description_outlined, color: AppColors.ok, size: 22),
                const SizedBox(width: 8),
                const Text('숙박일지 내보내기'),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('대상 월', style: TextStyle(fontSize: 11, color: context.brand.muted, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: busy ? null : () => shiftMonth(-1),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text(DateFormat('yyyy년 M월', 'ko').format(month),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                        IconButton(
                          onPressed: busy ? null : () => shiftMonth(1),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('지점', style: TextStyle(fontSize: 11, color: context.brand.muted, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: selected.length == branches.length,
                      title: const Text('전체', style: TextStyle(fontWeight: FontWeight.w700)),
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                                selected
                                  ..clear()
                                  ..addAll(v == true ? branches.map((b) => b.id) : const <String>[]);
                              }),
                    ),
                    for (final b in branches)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.only(left: 12),
                        controlAffinity: ListTileControlAffinity.leading,
                        value: selected.contains(b.id),
                        title: Text(b.name),
                        onChanged: busy
                            ? null
                            : (v) => setState(() {
                                  if (v == true) {
                                    selected.add(b.id);
                                  } else {
                                    selected.remove(b.id);
                                  }
                                }),
                      ),
                    const SizedBox(height: 4),
                    Text('※ 수령요금은 예약 데이터에 없어 빈칸으로 출력됩니다 (한글에서 수기 입력).',
                        style: TextStyle(fontSize: 11, color: context.brand.dim, height: 1.4)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.of(ctx).pop(),
                child: const Text('취소'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.ok),
                onPressed: busy || selected.isEmpty
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          await _export(ctx, ref, month, branches.where((b) => selected.contains(b.id)).toList());
                          if (ctx.mounted) Navigator.of(ctx).pop();
                        } catch (e) {
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text('내보내기 실패: $e'), backgroundColor: AppColors.danger),
                            );
                          }
                        } finally {
                          if (ctx.mounted) setState(() => busy = false);
                        }
                      },
                icon: busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.download, size: 18),
                label: Text(busy ? '생성 중...' : '내보내기'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 선택한 월·지점의 예약을 조회해 HWPX 바이트를 만들고 다운로드한다.
  Future<void> _export(
    BuildContext context,
    WidgetRef ref,
    DateTime month,
    List<BranchModel> branches,
  ) async {
    final fs = ref.read(firestoreProvider);
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 1);

    // checkIn(입실일) 기준 해당 월. 지점 필터는 클라이언트에서(복합 색인 회피).
    final snap = await fs
        .collection('reservations')
        .where('checkIn', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
        .where('checkIn', isLessThan: Timestamp.fromDate(monthEnd))
        .get();
    final all = snap.docs.map(ReservationModel.fromDoc).toList();
    final wanted = {for (final b in branches) b.id};

    // 지점별 표 구성 (요청 양식: 연번/날짜/성명/숙박일수/수령요금)
    final tables = <StayLogTable>[];
    for (final b in branches) {
      final rows = all.where((r) => r.branchId == b.id).toList()
        ..sort((a, c) => a.checkIn.compareTo(c.checkIn));
      if (rows.isEmpty) continue;
      var seq = 1;
      tables.add(StayLogTable(
        '${b.name} · ${DateFormat('yyyy년 M월', 'ko').format(month)}',
        [
          for (final r in rows)
            StayLogRow(
              seq: seq++,
              date: r.checkIn,
              name: r.guestName,
              nights: _nights(r.checkIn, r.checkOut),
            ),
        ],
      ));
    }

    if (tables.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${DateFormat('yyyy년 M월', 'ko').format(month)} 해당 지점 예약이 없습니다'),
            backgroundColor: AppColors.warn,
          ),
        );
      }
      return;
    }

    final title = '솔렌스테이 숙박일지 (${DateFormat('yyyy년 M월', 'ko').format(month)})';
    final bytes = buildStayLogHwpx(title: title, tables: tables);

    final branchTag = wanted.length == 1 ? '_${branches.first.name}' : '';
    final fileName = '솔렌스테이_숙박일지_${DateFormat('yyyy-MM').format(month)}$branchTag.hwpx';
    downloadBytes(fileName, bytes, mimeType: 'application/hwp+zip');

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$fileName 내보냈습니다'), backgroundColor: AppColors.ok),
      );
    }
  }

  /// 숙박일수 = (체크아웃 날짜 - 체크인 날짜). 같은 날이면 1박으로.
  int _nights(DateTime checkIn, DateTime checkOut) {
    final a = DateTime(checkIn.year, checkIn.month, checkIn.day);
    final b = DateTime(checkOut.year, checkOut.month, checkOut.day);
    final n = b.difference(a).inDays;
    return n <= 0 ? 1 : n;
  }
}
