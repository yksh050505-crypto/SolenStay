import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/services.dart';

/// 알림 모델
class NotificationItem {
  final String id;
  final String type; // 'new_cleaning' | 'manager_notice' | 'schedule_change' | 'general'
  final String title;
  final String body;
  final DateTime createdAt;
  final List<String> readByUids; // 읽음 처리한 사용자 uid들
  final Map<String, dynamic>? data; // 추가 데이터 (cleaningId 등)

  NotificationItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.readByUids,
    this.data,
  });

  bool isReadBy(String uid) => readByUids.contains(uid);

  factory NotificationItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return NotificationItem(
      id: doc.id,
      type: d['type'] as String? ?? 'general',
      title: d['title'] as String? ?? '',
      body: d['body'] as String? ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      readByUids: (d['readByUids'] as List<dynamic>?)?.cast<String>() ?? const [],
      data: d['data'] as Map<String, dynamic>?,
    );
  }
}

/// 현재 사용자의 알림 목록 (recipientUids에 본인 uid 포함된 것)
final notificationsProvider = StreamProvider<List<NotificationItem>>((ref) {
  final user = ref.watch(firebaseUserProvider).value;
  if (user == null) return Stream.value(const <NotificationItem>[]);

  return ref
      .watch(firestoreProvider)
      .collection('notifications')
      .where('recipientUids', arrayContains: user.uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(NotificationItem.fromDoc).toList());
});

/// 미읽 알림 개수 (현재 사용자 기준)
final unreadNotificationCountProvider = Provider<int>((ref) {
  final user = ref.watch(firebaseUserProvider).valueOrNull;
  if (user == null) return 0;
  final list = ref.watch(notificationsProvider).valueOrNull ?? const [];
  return list.where((n) => !n.isReadBy(user.uid)).length;
});

/// 매니저가 작성한 공지 목록 (senderUid = 본인)
final sentNoticesProvider = StreamProvider<List<NotificationItem>>((ref) {
  final user = ref.watch(firebaseUserProvider).value;
  if (user == null) return Stream.value(const <NotificationItem>[]);

  return ref
      .watch(firestoreProvider)
      .collection('notifications')
      .where('type', isEqualTo: 'manager_notice')
      .where('senderUid', isEqualTo: user.uid)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(NotificationItem.fromDoc).toList());
});

/// 알림 목록 페이지
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notiAsync = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('알림'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: notiAsync.when(
        loading: () => Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text('오류: $e', style: TextStyle(color: AppColors.danger), textAlign: TextAlign.center),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off_outlined, size: 56, color: context.brand.dim.withOpacity(0.5)),
                  SizedBox(height: 12),
                  Text('알림이 없습니다', style: TextStyle(color: context.brand.muted, fontSize: 14, fontWeight: FontWeight.w500)),
                  SizedBox(height: 4),
                  Text('새 청소 일정, 매니저 공지, 일정 변경 알림이 여기에 표시됩니다',
                      style: TextStyle(color: context.brand.dim, fontSize: 12),
                      textAlign: TextAlign.center),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: list.length,
            separatorBuilder: (_, __) => SizedBox(height: 8),
            itemBuilder: (_, i) => _NotificationCard(item: list[i]),
          );
        },
      ),
    );
  }
}

class _NotificationCard extends ConsumerWidget {
  final NotificationItem item;
  const _NotificationCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final iconData = _iconFor(item.type);
    final color = _colorFor(item.type);
    final cleaningId = item.data?['cleaningId'] as String?;
    final user = ref.watch(firebaseUserProvider).valueOrNull;
    final isRead = user != null && item.isReadBy(user.uid);

    return Material(
      color: context.brand.panel,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () async {
          // 클릭 시 읽음 처리 (본인 uid를 readByUids에 추가)
          if (user != null && !isRead) {
            await _markAsRead(ref, user.uid);
          }
          // 청소 알림은 청소 상세로 이동
          if (cleaningId != null && context.mounted) {
            context.push('/cleaning/$cleaningId');
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.brand.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(iconData, color: color, size: 18),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: TextStyle(
                              fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                              fontSize: 14,
                              color: context.brand.text,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          _formatTime(item.createdAt),
                          style: TextStyle(color: context.brand.dim, fontSize: 11),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      item.body,
                      style: TextStyle(
                        color: context.brand.muted,
                        fontSize: 12,
                        height: 1.4,
                        fontWeight: isRead ? FontWeight.w400 : FontWeight.w500,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!isRead) ...[
                SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.branch1,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 본인 uid를 readByUids에 추가 (Firestore 보안 규칙: arrayUnion 허용)
  Future<void> _markAsRead(WidgetRef ref, String uid) async {
    try {
      await ref
          .read(firestoreProvider)
          .collection('notifications')
          .doc(item.id)
          .update({
        'readByUids': FieldValue.arrayUnion([uid]),
      });
    } catch (_) {
      // 실패 시 무시 (다음 클릭 때 재시도)
    }
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'new_cleaning':
        return Icons.cleaning_services_outlined;
      case 'manager_notice':
        return Icons.campaign_outlined;
      case 'schedule_change':
        return Icons.event_repeat_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _colorFor(String type) {
    switch (type) {
      case 'new_cleaning':
        return AppColors.branch1;
      case 'manager_notice':
        return AppColors.warn;
      case 'schedule_change':
        return AppColors.ok;
      default:
        return AppColors.muted;
    }
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return '방금';
    if (diff.inHours < 1) return '${diff.inMinutes}분 전';
    if (diff.inDays < 1) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return DateFormat('M/d', 'ko').format(t);
  }
}
