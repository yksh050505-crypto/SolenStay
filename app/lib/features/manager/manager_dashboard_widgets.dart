import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// 날짜 기준 그룹 라벨(오늘/내일/이후/지남)을 계산한다.
String dateGroupLabel(DateTime date, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final d = DateTime(date.year, date.month, date.day);
  final diff = d.difference(today).inDays;
  if (diff < 0) return '지난 일정';
  if (diff == 0) return '오늘';
  if (diff == 1) return '내일';
  if (diff <= 7) return '이번 주';
  return '이후';
}

/// 그룹 라벨 정렬 우선순위(작을수록 먼저).
int dateGroupOrder(String label) {
  switch (label) {
    case '지난 일정':
      return 0;
    case '오늘':
      return 1;
    case '내일':
      return 2;
    case '이번 주':
      return 3;
    case '이후':
      return 4;
    default:
      return 9;
  }
}

/// 접기/펼치기 가능한 섹션. 헤더에 카운트 배지와 (선택) danger 표시.
/// 건수가 늘어도 기본 접힘으로 리스트 길이를 통제한다.
class CollapsibleSection extends StatefulWidget {
  final String title;
  final int count;
  final bool danger;
  final bool initiallyExpanded;
  final IconData? leadingIcon;
  final Widget child;

  const CollapsibleSection({
    super.key,
    required this.title,
    required this.count,
    this.danger = false,
    this.initiallyExpanded = false,
    this.leadingIcon,
    required this.child,
  });

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final accent = widget.danger ? AppColors.danger : context.brand.text;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: context.brand.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.brand.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 헤더 (탭하면 토글)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(
                  children: [
                    if (widget.danger) ...[
                      Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 16),
                      const SizedBox(width: 5),
                    ] else if (widget.leadingIcon != null) ...[
                      Icon(widget.leadingIcon, color: context.brand.muted, size: 16),
                      const SizedBox(width: 5),
                    ],
                    Text(
                      widget.title,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: accent),
                    ),
                    const SizedBox(width: 8),
                    // 카운트 배지
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: widget.count > 0
                            ? (widget.danger ? AppColors.danger : AppColors.branch1).withOpacity(0.12)
                            : context.brand.panel2,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${widget.count}',
                        style: TextStyle(
                          color: widget.count > 0
                              ? (widget.danger ? AppColors.danger : AppColors.branch1)
                              : context.brand.muted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(Icons.expand_more, color: context.brand.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 본문
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: widget.child,
            ),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}

/// 리스트를 초기 N개만 보여주고 "더보기"로 전체를 펼치는 위젯.
/// 건수가 많아도 화면이 끝없이 길어지지 않게 한다.
class ShowMoreList extends StatefulWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final int initialCount;

  const ShowMoreList({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.initialCount = 4,
  });

  @override
  State<ShowMoreList> createState() => _ShowMoreListState();
}

class _ShowMoreListState extends State<ShowMoreList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final showAll = _expanded || widget.itemCount <= widget.initialCount;
    final visible = showAll ? widget.itemCount : widget.initialCount;
    final hidden = widget.itemCount - visible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < visible; i++) widget.itemBuilder(context, i),
        if (!showAll)
          TextButton.icon(
            onPressed: () => setState(() => _expanded = true),
            icon: const Icon(Icons.expand_more, size: 18),
            label: Text('$hidden건 더보기'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.branch1,
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          )
        else if (widget.itemCount > widget.initialCount)
          TextButton.icon(
            onPressed: () => setState(() => _expanded = false),
            icon: const Icon(Icons.expand_less, size: 18),
            label: const Text('접기'),
            style: TextButton.styleFrom(
              foregroundColor: context.brand.muted,
              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

/// 작은 날짜 그룹 헤더(오늘/내일/이후 등).
class DateGroupHeader extends StatelessWidget {
  final String label;
  final int count;
  const DateGroupHeader({super.key, required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    final danger = label == '지난 일정';
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: danger ? AppColors.danger : context.brand.muted,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.brand.dim),
          ),
        ],
      ),
    );
  }
}
