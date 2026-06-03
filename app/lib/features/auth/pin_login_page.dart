import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart' show kPrefAutoLogin;
import '../../core/theme.dart';
import '../../core/fcm.dart';
import '../../core/error_messages.dart';
import '../../data/services.dart';

/// ① PIN 로그인 — 이름 선택 + 6자리 PIN 입력 (네이티브 키패드 사용)
class PinLoginPage extends ConsumerStatefulWidget {
  const PinLoginPage({super.key});

  @override
  ConsumerState<PinLoginPage> createState() => _PinLoginPageState();
}

class _PinLoginPageState extends ConsumerState<PinLoginPage> {
  String? _selectedName;
  final _pinCtrl = TextEditingController();
  final _pinFocus = FocusNode();
  bool _loading = false;
  String? _error;
  bool _adminMode = false; // false: 청소원 / true: 매니저·실장
  bool _autoLogin = false; // 이 기기에서 자동 로그인 유지 여부
  Future<List<String>>? _candidatesFuture; // 캐시: _adminMode 바뀔 때만 재호출

  @override
  void initState() {
    super.initState();
    _candidatesFuture = ref.read(functionsServiceProvider).listLoginCandidates(adminOnly: _adminMode);
    // SharedPreferences에서 현재 자동 로그인 설정 읽어옴 (기본 false)
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() => _autoLogin = prefs.getBool(kPrefAutoLogin) ?? false);
    });
  }

  void _reloadCandidates() {
    setState(() {
      _candidatesFuture = ref.read(functionsServiceProvider).listLoginCandidates(adminOnly: _adminMode);
    });
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selectedName == null) {
      setState(() => _error = '이름을 선택하세요');
      return;
    }
    final pin = _pinCtrl.text;
    if (pin.length < 4) {
      setState(() => _error = 'PIN 4자리 이상 입력');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fn = ref.read(functionsServiceProvider);
      final result = await fn.signInWithPin(name: _selectedName!, pin: pin);
      final token = result['token'] as String;
      final cred = await FirebaseAuth.instance.signInWithCustomToken(token);
      // 토큰 강제 새로고침 - Custom Claims가 Firestore 요청에 즉시 반영되도록
      await cred.user?.getIdTokenResult(true);
      // 사용자가 선택한 자동 로그인 설정을 디바이스에 저장
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(kPrefAutoLogin, _autoLogin);
      } catch (_) {}
      // FCM 토큰 등록 (권한 요청 + 서버에 토큰 저장)
      // ignore: unawaited_futures
      initFcmForUser(fn);
    } catch (e) {
      setState(() {
        _error = friendlyError(e);
        _pinCtrl.clear();
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _modeButton({required String label, required bool selected, required VoidCallback onTap}) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      elevation: selected ? 1 : 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected
                  ? (label == '관리자' ? AppColors.danger : AppColors.branch1)
                  : AppColors.muted,
            ),
          ),
        ),
      ),
    );
  }

  void _onSelectName(String name) {
    setState(() {
      _selectedName = name;
      _error = null;
    });
    // 이름 선택 직후 PIN 입력으로 포커스 이동
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _pinFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth > 420 ? 400.0 : screenWidth;

    return Scaffold(
      backgroundColor: AppColors.bg,
      // 키보드가 올라올 때 화면이 자동으로 조정되도록
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: SizedBox(
            width: maxWidth,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Column(
                children: [
                  // 로고
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAEDD0),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF3B2516).withOpacity(0.12),
                          blurRadius: 30,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'SOLEN\nSTAY',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'serif',
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF3B2516),
                          height: 1.1,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'SolenStay',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _adminMode ? '관리자 로그인' : '청소 관리 시스템',
                    style: TextStyle(
                      color: _adminMode ? AppColors.danger : AppColors.muted,
                      fontSize: 13,
                      fontWeight: _adminMode ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 모드 토글 (청소원 / 관리자)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.panel2,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _modeButton(
                            label: '직원',
                            selected: !_adminMode,
                            onTap: () {
                              if (_adminMode == false) return;
                              setState(() {
                                _adminMode = false;
                                _selectedName = null;
                                _pinCtrl.clear();
                                _error = null;
                              });
                              _reloadCandidates();
                            },
                          ),
                        ),
                        Expanded(
                          child: _modeButton(
                            label: '관리자',
                            selected: _adminMode,
                            onTap: () {
                              if (_adminMode == true) return;
                              setState(() {
                                _adminMode = true;
                                _selectedName = null;
                                _pinCtrl.clear();
                                _error = null;
                              });
                              _reloadCandidates();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 이름 카드 (캐시된 future 사용 — 매 빌드 재호출 방지)
                  FutureBuilder<List<String>>(
                    future: _candidatesFuture,
                    builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator());
                        }
                        if (snap.hasError) {
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.error_outline, color: AppColors.danger, size: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '사용자 목록 로드 실패',
                                    style: TextStyle(color: AppColors.danger, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        final names = snap.data ?? const <String>[];
                        if (names.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(20),
                            child: Text('등록된 사용자가 없습니다.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '이름을 선택하세요',
                              style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 2.6,
                              ),
                              itemCount: names.length,
                              itemBuilder: (_, i) {
                                final n = names[i];
                                final selected = _selectedName == n;
                                return Material(
                                  color: selected ? AppColors.branch1.withOpacity(0.08) : AppColors.panel,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    onTap: () => _onSelectName(n),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: selected ? AppColors.branch1 : AppColors.line,
                                          width: selected ? 2 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          CircleAvatar(
                                            radius: 15,
                                            backgroundColor: selected ? AppColors.branch1 : AppColors.dim,
                                            child: Text(
                                              n.isNotEmpty ? n[0] : '?',
                                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            n,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                              color: selected ? AppColors.branch1 : AppColors.text,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),

                  const SizedBox(height: 24),

                  // PIN 라벨
                  const Text(
                    'PIN 입력',
                    style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),

                  // PIN dots (시각적 표시)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(6, (i) {
                      final filled = i < _pinCtrl.text.length;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: filled ? 16 : 14,
                        height: filled ? 16 : 14,
                        decoration: BoxDecoration(
                          color: filled ? AppColors.branch1 : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: filled ? AppColors.branch1 : AppColors.line,
                            width: 2,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 18),

                  // PIN 입력 TextField (네이티브 키패드 호출)
                  TextField(
                    controller: _pinCtrl,
                    focusNode: _pinFocus,
                    keyboardType: const TextInputType.numberWithOptions(decimal: false, signed: false),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    obscureText: true,
                    obscuringCharacter: '●',
                    autofocus: false,
                    enabled: !_loading,
                    enableSuggestions: false,
                    autocorrect: false,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 16,
                      color: AppColors.text,
                    ),
                    decoration: InputDecoration(
                      hintText: '숫자 6자리',
                      hintStyle: TextStyle(
                        color: AppColors.dim,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      counter: const SizedBox.shrink(),
                    ),
                    onChanged: (value) {
                      setState(() => _error = null);
                      if (value.length == 6) {
                        // 6자리 입력 완료 시 자동 제출
                        _pinFocus.unfocus();
                        _submit();
                      }
                    },
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 10),

                  // 자동 로그인 체크박스 — 이 기기에서 다음 시작 시 PIN 생략
                  InkWell(
                    onTap: _loading
                        ? null
                        : () => setState(() => _autoLogin = !_autoLogin),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: Checkbox(
                              value: _autoLogin,
                              onChanged: _loading
                                  ? null
                                  : (v) => setState(() => _autoLogin = v ?? false),
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              '이 기기에서 자동 로그인',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: AppColors.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // 로그인 버튼 (수동 제출용)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _loading ? null : _submit,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : const Text('로그인', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),

                  // 에러 메시지
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.danger, size: 16),
                          const SizedBox(width: 6),
                          Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
