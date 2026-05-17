import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/services.dart';
import '../cleaning_detail/cleaning_detail_page.dart';
import '../shared/bottom_nav.dart';

/// ④ 완료 보고 (사진 + 메모) - 목업 디자인 적용
class CompletionPage extends ConsumerStatefulWidget {
  final String cleaningId;
  const CompletionPage({super.key, required this.cleaningId});

  @override
  ConsumerState<CompletionPage> createState() => _CompletionPageState();
}

class _CompletionPageState extends ConsumerState<CompletionPage> {
  final _memoCtrl = TextEditingController();
  final List<_PhotoEntry> _photos = [];
  bool _submitting = false;

  @override
  void dispose() {
    _memoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cleaningAsync = ref.watch(cleaningProvider(widget.cleaningId));
    final branches = ref.watch(branchesProvider).value ?? const <BranchModel>[];
    final user = ref.watch(currentUserProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('완료 보고'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      bottomNavigationBar: const AppBottomNav(active: BottomTab.home),
      body: cleaningAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('오류: $e')),
        data: (cleaning) {
          if (cleaning == null) {
            return const Center(child: Text('청소 작업을 찾을 수 없습니다.'));
          }
          if (cleaning.isCompleted) {
            return _CompletedView(cleaning: cleaning, branches: branches);
          }
          final branch = branches.firstWhere(
            (b) => b.id == cleaning.branchId,
            orElse: () => BranchModel(id: cleaning.branchId, name: cleaning.branchId, rooms: 0, maxOccupancy: 0, color: '#64748B', iCalSourceUrl: '', active: true),
          );
          final reservationAsync = ref.watch(reservationProvider(cleaning.reservationId));
          return _buildForm(cleaning, branch, reservationAsync.value, user);
        },
      ),
    );
  }

  Widget _buildForm(CleaningModel cleaning, BranchModel branch, ReservationModel? reservation, UserModel? user) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
            children: [
              // 호점 + 날짜 (중앙 정렬)
              Column(
                children: [
                  Text(branch.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('yyyy-MM-dd (E)', 'ko').format(cleaning.scheduledDate),
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 사진 섹션
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('완료 사진', style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                  Text('${_photos.length}/${AppConstants.maxPhotos}', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 8),
              // 사진 첨부 버튼 (점선 테두리)
              OutlinedButton.icon(
                onPressed: _photos.length >= AppConstants.maxPhotos ? null : _pickPhotos,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: AppColors.branch1.withOpacity(0.5), style: BorderStyle.solid, width: 1.5),
                  backgroundColor: AppColors.branch1.withOpacity(0.06),
                  foregroundColor: AppColors.branch1,
                ),
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('사진 첨부 (복수 선택)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              if (_photos.isNotEmpty) ...[
                const SizedBox(height: 10),
                _PhotoGrid(
                  photos: _photos,
                  onRemove: (i) => setState(() => _photos.removeAt(i)),
                ),
              ],
              const SizedBox(height: 18),

              // 특이사항 메모
              const Text('특이사항 메모', style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              TextField(
                controller: _memoCtrl,
                maxLines: 4,
                maxLength: 500,
                decoration: const InputDecoration(
                  hintText: '특이사항이 있으면 입력해주세요...',
                  hintStyle: TextStyle(color: AppColors.dim, fontSize: 13),
                ),
              ),
              const SizedBox(height: 10),

              // 요약 카드
              _SummaryCard(
                branch: branch,
                cleaning: cleaning,
                reservation: reservation,
                user: user,
              ),
            ],
          ),
        ),

        // 완료 처리하기 버튼 (초록색)
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : () => _submit(cleaning),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.ok,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _submitting
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                        SizedBox(width: 10),
                        Text('제출 중...', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ],
                    )
                  : const Text('완료 처리하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickPhotos() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(imageQuality: 70, maxWidth: 1200);
    if (images.isEmpty) return;

    final remaining = AppConstants.maxPhotos - _photos.length;
    final toAdd = images.take(remaining);

    for (final img in toAdd) {
      final bytes = await img.readAsBytes();
      if (bytes.length > AppConstants.photoMaxSizeBytes) continue;
      setState(() => _photos.add(_PhotoEntry(name: img.name, bytes: bytes)));
    }
  }

  Future<void> _submit(CleaningModel cleaning) async {
    setState(() => _submitting = true);
    try {
      final List<String> photoUrls = [];
      final storage = FirebaseStorage.instance;
      for (int i = 0; i < _photos.length; i++) {
        final photo = _photos[i];
        final path = 'cleanings/${cleaning.id}/photo_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final uploadRef = storage.ref(path);
        await uploadRef.putData(photo.bytes, SettableMetadata(contentType: 'image/jpeg'));
        final url = await uploadRef.getDownloadURL();
        photoUrls.add(url);
      }

      await ref.read(functionsServiceProvider).completeCleaning(
            cleaningId: cleaning.id,
            checklist: cleaning.checklist,
            photoUrls: photoUrls,
            memo: _memoCtrl.text.trim(),
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('완료 보고가 제출되었습니다!'), backgroundColor: AppColors.ok),
        );
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('제출 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

// ===== 요약 카드 =====

class _SummaryCard extends StatelessWidget {
  final BranchModel branch;
  final CleaningModel cleaning;
  final ReservationModel? reservation;
  final UserModel? user;
  const _SummaryCard({required this.branch, required this.cleaning, required this.reservation, required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.panel2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _row('호점', branch.name),
          _divider(),
          _row('이전 게스트', reservation != null ? '${reservation!.guestName} · 👤 ${reservation!.guestCount}인' : '-'),
          _divider(),
          _row('다음 체크인', reservation != null ? '${reservation!.guestName} · 👤 ${reservation!.guestCount}인' : '-', valueColor: AppColors.warn),
          _divider(),
          _row('담당', user?.name ?? '-', last: true),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor, bool last = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          Flexible(
            child: Text(
              value,
              style: TextStyle(color: valueColor ?? AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        height: 1,
        margin: EdgeInsets.zero,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line, width: 1, style: BorderStyle.solid)),
        ),
      );
}

// ===== 사진 그리드 (3열) =====

class _PhotoEntry {
  final String name;
  final Uint8List bytes;
  _PhotoEntry({required this.name, required this.bytes});
}

class _PhotoGrid extends StatelessWidget {
  final List<_PhotoEntry> photos;
  final void Function(int) onRemove;
  const _PhotoGrid({required this.photos, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: photos.length,
      itemBuilder: (_, i) => Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(photos[i].bytes, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () => onRemove(i),
              child: Container(
                width: 22, height: 22,
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== 완료된 작업 보기 =====

class _CompletedView extends StatelessWidget {
  final CleaningModel cleaning;
  final List<BranchModel> branches;
  const _CompletedView({required this.cleaning, required this.branches});

  @override
  Widget build(BuildContext context) {
    final branch = branches.firstWhere(
      (b) => b.id == cleaning.branchId,
      orElse: () => BranchModel(id: cleaning.branchId, name: cleaning.branchId, rooms: 0, maxOccupancy: 0, color: '#64748B', iCalSourceUrl: '', active: true),
    );

    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.ok.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              const Icon(Icons.check_circle, color: AppColors.ok, size: 48),
              const SizedBox(height: 8),
              const Text('청소 완료', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.ok)),
              const SizedBox(height: 4),
              Text(
                '${branch.name} · ${DateFormat('yyyy-MM-dd', 'ko').format(cleaning.scheduledDate)}',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (cleaning.photoUrls.isNotEmpty) ...[
          const Text('첨부 사진', style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1,
            ),
            itemCount: cleaning.photoUrls.length,
            itemBuilder: (_, i) => ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(cleaning.photoUrls[i], fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 16),
        ],

        if (cleaning.memo.isNotEmpty) ...[
          const Text('메모', style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.line),
            ),
            child: Text(cleaning.memo, style: const TextStyle(fontSize: 13, height: 1.5)),
          ),
        ],
      ],
    );
  }
}
