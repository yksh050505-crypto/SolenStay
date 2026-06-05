import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';

/// 도움말 / 문의 페이지
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final faqs = <(String, String)>[
      (
        l.t('PIN을 잊어버렸어요', 'I forgot my PIN'),
        l.t('매니저에게 PIN 초기화를 요청하세요. 초기화 후 다음 로그인에서 새 PIN을 설정합니다.',
            'Ask your manager to reset your PIN. You will set a new one at next login.'),
      ),
      (
        l.t('청소를 내가 맡으려면?', 'How do I claim a cleaning?'),
        l.t('일정 화면에서 미배정 청소를 열고 "내가 할게요"를 누르면 배정됩니다.',
            'Open an unassigned cleaning in the Schedule tab and tap "I\'ll take it".'),
      ),
      (
        l.t('완료 보고는 어떻게 하나요?', 'How do I submit a completion report?'),
        l.t('청소 상세에서 체크리스트를 모두 체크하고 사진을 첨부한 뒤 완료를 누르세요.',
            'On the cleaning detail, check all checklist items, attach photos, then tap Complete.'),
      ),
      (
        l.t('이름이나 사진을 바꾸려면?', 'How do I change my name or photo?'),
        l.t('내정보 > 이름 / 프로필 사진에서 변경할 수 있습니다.',
            'Go to My Info > Name / Profile photo.'),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('도움말 / 문의', 'Help / Contact')),
        leading: IconButton(icon: Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            // 문의 안내
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.branch1.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.branch1.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.branch1.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.support_agent, color: AppColors.branch1, size: 22),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l.t('문의 안내', 'Need help?'),
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        SizedBox(height: 2),
                        Text(
                          l.t('앱 사용 중 문제가 있으면 담당 매니저에게 문의해 주세요.',
                              'If you run into any issue, please contact your manager.'),
                          style: TextStyle(color: context.brand.muted, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 22),

            Text(
              l.t('자주 묻는 질문', 'Frequently asked'),
              style: TextStyle(
                color: context.brand.muted,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 10),
            ...faqs.map((f) => _FaqTile(question: f.$1, answer: f.$2)),
          ],
        ),
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;
  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.brand.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.brand.line),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          shape: Border(),
          onExpansionChanged: (v) => setState(() => _open = v),
          title: Text(
            widget.question,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          trailing: Icon(_open ? Icons.expand_less : Icons.expand_more, color: context.brand.muted),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.answer,
                style: TextStyle(color: context.brand.muted, fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
