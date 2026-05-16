import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/theme.dart';
import '../../data/services.dart';

/// ① PIN 로그인 — 이름 선택 + 6자리 PIN 입력 (디자인 목업과 동일 구조)
class PinLoginPage extends ConsumerStatefulWidget {
  const PinLoginPage({super.key});

  @override
  ConsumerState<PinLoginPage> createState() => _PinLoginPageState();
}

class _PinLoginPageState extends ConsumerState<PinLoginPage> {
  String? _selectedName;
  String _pin = '';
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (_selectedName == null) {
      setState(() => _error = '이름을 선택하세요');
      return;
    }
    if (_pin.length < 4) {
      setState(() => _error = 'PIN 4자리 이상 입력');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fn = ref.read(functionsServiceProvider);
      final result = await fn.signInWithPin(name: _selectedName!, pin: _pin);
      final token = result['token'] as String;
      await FirebaseAuth.instance.signInWithCustomToken(token);
      // 라우터가 자동으로 /home으로 보냄
    } catch (e) {
      setState(() {
        _error = e.toString().contains('invalid name or pin')
            ? '이름 또는 PIN이 올바르지 않습니다'
            : '로그인 실패: ${e.toString()}';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
          child: Column(
            children: [
              // 로고
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAEDD0),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3B2516).withOpacity(0.18),
                      blurRadius: 40,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'SOLEN\nSTAY',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'serif',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3B2516),
                      height: 1.05,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text('SolenStay', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text('PIN 로그인', style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 28),

              // 이름 카드 (Cloud Function 호출, 인증 없이)
              Consumer(builder: (context, ref, _) {
                return FutureBuilder<List<String>>(
                  future: ref.read(functionsServiceProvider).listLoginCandidates(),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('사용자 목록 로드 실패: ${snap.error}', style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                      );
                    }
                    final names = snap.data ?? const <String>[];
                    if (names.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('등록된 사용자가 없습니다.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                      );
                    }
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 2.4,
                      ),
                      itemCount: names.length,
                      itemBuilder: (_, i) {
                        final n = names[i];
                        final selected = _selectedName == n;
                        return InkWell(
                          onTap: () => setState(() => _selectedName = n),
                          child: Container(
                            decoration: BoxDecoration(
                              color: selected ? const Color(0x1A3B82F6) : AppColors.panel,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: selected ? AppColors.branch1 : AppColors.line),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: AppColors.branch1,
                                  child: Text(n.isNotEmpty ? n[0] : '?', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                                ),
                                const SizedBox(width: 8),
                                Text(n, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              }),

              const SizedBox(height: 18),

              // PIN dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) {
                  final filled = i < _pin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                      color: filled ? AppColors.branch1 : AppColors.panel2,
                      shape: BoxShape.circle,
                      border: Border.all(color: filled ? AppColors.branch1 : AppColors.line, width: 2),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),

              // 키패드
              SizedBox(
                width: double.infinity,
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.6,
                  ),
                  itemCount: 12,
                  itemBuilder: (_, i) {
                    if (i == 9) return const SizedBox.shrink();
                    final label = i == 10 ? '0' : i == 11 ? '⌫' : '${i + 1}';
                    return InkWell(
                      onTap: () {
                        setState(() {
                          if (i == 11) {
                            if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
                          } else if (_pin.length < 6) {
                            _pin += label;
                            if (_pin.length == 6) _submit();
                          }
                        });
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.panel,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.line),
                        ),
                        alignment: Alignment.center,
                        child: Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                      ),
                    );
                  },
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
              ],

              if (_loading) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
