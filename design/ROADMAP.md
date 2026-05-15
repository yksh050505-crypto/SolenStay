# SolenStay 구현 절차 (Roadmap)

> 1·2·3호점 예약·청소 관리 PWA (Flutter Web + Firebase)
> 최종 업데이트: 2026-05-16

---

## ✅ Phase 1. 디자인 (완료)

- 화면 7개 HTML 목업 (`design/mockup.html`)
  - ① 로그인 (PIN+이름)
  - ② 오늘의 청소 (홈)
  - ③ 작업 상세 (체크리스트)
  - ④ 완료 보고 (사진+메모)
  - ⑤ 캘린더 (앞으로 일정)
  - ⑥ 내정보 (프로필/설정)
  - ⑦ 매니저 대시보드
- 색상 팔레트: 1호점 `#3B82F6` · 2호점 `#10B981` · 3호점 `#F97316`
- 라이트 테마, Pretendard 폰트

---

## 🔧 Phase 2. 백엔드 셋업 (다음 단계)

**필요 설치** *(사용자가 직접)*
- [ ] Node.js LTS
- [ ] Firebase CLI (`npm install -g firebase-tools`)

**Firebase 프로젝트**
- [ ] Firebase 콘솔에서 새 프로젝트 생성 (또는 기존 `solenstay-f4817` 사용)
- [ ] 사용 서비스 활성화: Authentication, Firestore, Storage, Functions, Hosting, Cloud Messaging
- [ ] iOS/Android 미사용 — Web 앱만 등록

**데이터 모델 설계** *(AI와 함께)*
- [ ] Firestore 컬렉션 정의
  - `branches` (1·2·3호점 정보, iCal URL)
  - `users` (청소원/매니저, PIN 해시)
  - `reservations` (iCal 동기화된 예약)
  - `cleanings` (청소 작업 + 체크리스트 + 사진)
  - `notes` (특이사항)
- [ ] 보안 룰 (Firestore Rules)
- [ ] PIN 인증용 Custom Token Cloud Function
- [ ] iCal 동기화 Scheduled Function (15분 주기)
- [ ] FCM 푸시 알림 Function (새 청소 일정 / 미지정 알림)

---

## 💻 Phase 3. Flutter 웹앱 개발

**프로젝트 셋업**
- [ ] `flutter create solenstay --platforms=web`
- [ ] 패키지 추가: `firebase_core`, `cloud_firestore`, `firebase_auth`, `firebase_storage`, `firebase_messaging`, `go_router`, `riverpod`, `intl`, `image_picker`
- [ ] Firebase 연결 (`flutterfire configure`)

**핵심 구현**
- [ ] 라우팅 (`go_router`)
- [ ] 상태 관리 (`riverpod`)
- [ ] 7개 화면 위젯 구현 (목업 → Flutter)
- [ ] PIN 로그인 (이름 선택 → PIN 입력 2단계)
- [ ] 사진 다중 업로드 (Firebase Storage)
- [ ] 푸시 알림 (FCM Web)
- [ ] PWA 설정 (manifest, service worker, 홈화면 추가 안내)

---

## 🧪 Phase 4. 테스트 & 배포

**테스트**
- [ ] 청소원 흐름: 로그인 → 오늘 청소 → 작업 상세 → 완료 보고
- [ ] 매니저 흐름: 대시보드 → 미지정 청소 확인 → 특이사항 확인
- [ ] iCal 동기화 (테스트 예약 추가 → 15분 내 반영)
- [ ] 푸시 알림 수신 (PWA 설치 후 백그라운드 알림)
- [ ] 모바일 브라우저 (iOS Safari, Android Chrome) 동작 확인

**배포**
- [ ] `firebase deploy --only hosting`
- [ ] 도메인 연결 (선택)
- [ ] 다른 PC/폰에서 URL 접속 확인

---

## 🚀 Phase 5. 운영 시작

- [ ] 청소원 4명 PIN 발급 (김지영/박미선/이수정/최유나)
- [ ] 매니저 계정 발급
- [ ] 1·2·3호점 정보 입력
- [ ] OTA iCal URL 입력 (Airbnb, Booking.com 각 호점)
- [ ] 청소원 교육 (PWA 설치 + 사용법)
- [ ] 운영 1주차 피드백 수집 → v0.2 개선

---

## 📌 참고

- **레포**: https://github.com/yksh050505-crypto/SolenStay
- **디자인 미리보기**: https://yksh050505-crypto.github.io/SolenStay/design/mockup.html
- **로컬 작업 디렉토리**: `C:\SolenStay\` (worktree: `C:\SolenStay-pages\`)
- **개발 환경 (확인됨)**: Flutter 3.41.9, Dart 3.11.5, Git, VS Code, Chrome
- **추가 설치 필요**: Node.js, Firebase CLI
