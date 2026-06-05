import 'package:flutter/material.dart';
import 'theme.dart';

/// 통일된 로딩 인디케이터
class AppLoader extends StatelessWidget {
  final String? label;
  final double size;
  const AppLoader({super.key, this.label, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size, height: size,
            child: const CircularProgressIndicator(strokeWidth: 2.5),
          ),
          if (label != null) ...[
            SizedBox(height: 10),
            Text(label!, style: TextStyle(color: context.brand.muted, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

/// 통일된 빈 상태
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: context.brand.dim.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: context.brand.dim),
          ),
          SizedBox(height: 14),
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.brand.text)),
          if (subtitle != null) ...[
            SizedBox(height: 4),
            Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: context.brand.muted)),
          ],
          if (action != null) ...[
            SizedBox(height: 14),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 친화적 에러 박스
class AppErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const AppErrorBox({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: Text('다시 시도', style: TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}
