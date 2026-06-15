# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

SolenStay — 1·2·3호점(3개 지점) 숙소 **예약·청소 관리** 앱. OTA(에어비앤비 등) → Google Calendar 통합 iCal → Cloud Functions가 동기화 → 직원이 청소를 "참석(claim)"하고 사진·메모로 완료 보고하는 워크플로우.

- **앱**: Flutter (Android 네이티브 APK + Web/PWA). 역할 3종: `manager`(매니저) / `chief`(실장) / `cleaner`(청소원).
- **백엔드**: Firebase (Auth · Firestore · Functions · Storage · Hosting · FCM), 프로젝트 `solenstay-74f8e`.
- **자동화**: Zapier로 OTA iCal → Google Calendar 통합 피드, 그 피드를 Functions가 1분마다 동기화.
- 라이브 웹: https://solenstay-74f8e.web.app · 콘솔: https://console.firebase.google.com/project/solenstay-74f8e

## Commands

### Flutter 앱 (`app/`)
```bash
flutter pub get
flutter analyze                                  # 린트 (CI 없음 — 수동)
flutter run -d chrome --web-port 5000            # 웹 디버그. firebase_options.dart로 운영 Firebase에 직접 연결됨(주의: 실데이터)
flutter test                                     # 테스트(있는 경우)
flutter build apk --release                      # → build/app/outputs/flutter-apk/app-release.apk  (서명 주의: 아래 참조)
flutter build web --release                      # → build/web  (hosting public 경로)
```
환경: Flutter SDK `C:\src\flutter`, Android SDK `%LOCALAPPDATA%\Android\Sdk`, JDK 21. 빌드 요구: compileSdk 36 / NDK 27.0.12077973 / AGP 8.9.1 / Kotlin 2.1.0 (`app/android/app/build.gradle.kts`).

### Cloud Functions (`functions/`)
```bash
npm run build      # tsc
npm run lint       # tsc --noEmit (타입 체크가 곧 린트)
npm run serve      # build + firebase emulators:start --only functions
npm run deploy     # firebase deploy --only functions
npm run logs
```

### 배포
```bash
firebase deploy --only hosting     # public = app/build/web (먼저 flutter build web 필요)
firebase deploy --only functions
firebase deploy --only firestore:rules,storage   # 규칙
```
`firebase login` 은 PowerShell 실행정책에 막히면 `firebase.cmd login` 사용. 운영 스크립트(`scripts/`)는 로컬 키 없이 **Google Cloud Shell(ADC)** 에서 실행 (scripts/README 참고).

## ⚠️ APK 서명 — 반드시 원본 키 재사용

릴리스 APK는 **별도 release 키 없이 debug 키로 서명**된다 (`app/android/app/build.gradle.kts`: `signingConfig = signingConfigs.getByName("debug")`). 따라서 빌드 PC가 바뀌면 debug 키가 달라져 **기존 설치 앱과 서명 불일치 → "앱이 설치되지 않음"** 으로 업데이트가 거부된다.

- **원본 키**: `C:\Users\FORYOUCOM\OneDrive\Desktop\debug.keystore` (표준 debug 자격: storepass/keypass=`android`, alias=`androiddebugkey`). SHA-1 `AA:6F:5E:50:C2:FC:67:A9:A1:2D:A7:99:33:B0:D9:9B:F7:22:16:F8`, 2056년까지 유효.
- **새 환경에서 빌드 전**: 이 파일을 `~/.android/debug.keystore` 로 복사 후 빌드. 빌드 후 `apksigner verify --print-certs <apk>` 로 SHA-256 `EF1458313F...` 인지 확인.
- 키스토어는 git에 없음(`.gitignore`: `**/*.keystore`, `**/*.jks`, `key.properties`). 잃어버리면 전 직원 삭제·재설치해야 업데이트 가능.

## 앱 업데이트/릴리스 절차 (`docs/UPDATE.md`)

1. `app/pubspec.yaml` 의 **`version:` 한 줄만** 변경 (`x.y.z+N`). `versionCode`/`versionName`은 `flutter.versionCode`/`flutter.versionName`으로 자동 연동되므로 이 한 줄이 전부. **빌드번호 `+N`은 단조 증가** 필수(감소 금지).
2. `flutter build apk --release` (원본 키로 서명).
3. 매니저가 **PC 크롬 → 관리자 설정 → 앱 버전(Android) → 새 버전 등록** 에서 APK 업로드 → Firestore `config/appVersion` 갱신.
4. 직원 앱이 시작 시 버전 비교 → 업데이트 다이얼로그(`update_checker.dart`). **iPhone은 네이티브 없음** — Safari 웹앱(새로고침이 곧 최신).

## Architecture (big picture)

### Flutter (`app/lib`)
- **상태관리**: Riverpod. 데이터는 거의 전부 `data/services.dart`의 Firestore `StreamProvider`로 실시간 구독. **라우팅**: `app_router.dart`의 go_router — 비로그인 시 `/`(PIN 로그인)로 redirect 가드.
- **인증(PIN 기반)**: `signInWithPin` Cloud Function이 `role` claim 담은 **Custom Token** 발급 → `signInWithCustomToken` → `getIdTokenResult(true)`로 claim 즉시 반영. `main.dart`는 자동로그인 미설정 시 시작할 때 `signOut()`.
- 모든 callable은 `FunctionsService`(services.dart)로 감싸 호출. 모델은 `data/models.dart` (`UserModel`/`BranchModel`/`ReservationModel`/`CleaningModel`/`ChecklistItem`/`AppVersionModel`).
- `core/`: `theme.dart`(다크/라이트 `BrandColors`, 호점색 `AppColors.branchColor`/`branchShortLabel` — branch1 파랑·branch2 하늘·branch3 보라), `fcm.dart`(자동 권한요청 안 함 — 내정보에서 명시적 요청), `l10n.dart`.
- `features/`: `auth`(pin_login), `home`, `cleaning_detail`, `completion`(사진 직접 Storage 업로드), `calendar`, `manager`(dashboard + dashboard_widgets), `admin`(settings, reservation_management, apk_picker_web/stub), `notifications`, `profile`, `update`, `help`.

### Cloud Functions (`functions/src`, TypeScript, nodejs20, **region `asia-northeast3`**)
`index.ts`가 전부 re-export. 트리거 유형별:
- `auth_pin.ts` — PIN은 **HMAC-SHA256 + per-user salt** 해시 저장(`helpers.ts`). `listLoginCandidates`/`signInWithPin`은 **인증 불필요**(`minInstances:1`). 사용자 CRUD·`updateMyProfile`(규칙상 직접 못 바꾸는 필드 경유).
- `ical_sync.ts` — `syncICalScheduled` **매 1분**(`constants.ts`): 활성 호점별 iCal fetch → `reservations` upsert + 피드에서 사라진 미래 예약 삭제.
- `cleanings.ts` — `onReservationCreated`: 같은 doc id로 `cleanings` 생성, `scheduledDate = reservation.checkOut`, 체크리스트 템플릿 복사. `claim`/`release`/`completeCleaning`(트랜잭션, 완료 시 "다음 게스트" 스냅샷 캡처). `forceAssignCleaning`.
- `notifications.ts` — 예약 create/update/delete onDocument 트리거 FCM + `notifications` 이력, 미배정 리마인더(스케줄), 매니저 공지, FCM 토큰 등록/무효토큰 정리.
- `calendar.ts` — `myCalendar`(onRequest, **인증 없이 토큰으로** 본인 청소를 `.ics`로 반환), 토큰 발급/회수.
- `maintenance.ts` — 매일 30일 지난 완료 청소의 Storage 사진 삭제.

### 데이터 / 규칙
- Firestore: `users`, `branches`, `reservations`, `cleanings`, `checklistTemplates`, `notifications`, `config/appVersion`.
- `firestore.rules`/`storage.rules`는 **Custom Claims `request.auth.token.role`** 기반(DB 조회 없음). 주의: `cleanings` update 규칙이 넓음 — 담당자/실장/매니저가 **전체 필드** 수정 가능. 완료 검증(체크리스트 등)은 규칙이 아니라 `completeCleaning` 함수에만 있다.

## 주의/관례 (non-obvious)

- **버전은 `app/pubspec.yaml`의 `version:` 한 줄만** 바꾼다(나머지 자동 파생).
- **청소 ↔ 예약은 같은 doc id로 1:1.** `cleanings.scheduledDate`는 생성 시 1회만 기록되고 이후 어떤 동기화도 덮어쓰지 않는다(예약 수정해도 청소 날짜 불변). 단 예약이 피드에서 사라지면(미래 checkOut) 해당 청소가 자동 삭제됨(`ical_sync.ts`).
- `ReservationManagementPage`는 매니저 권한으로 `cleanings`를 **클라이언트에서 직접 set** → `onReservationCreated` 트리거와 경합 가능(알려진 이슈).
- **캘린더 pill**(`calendar_page.dart`): `BoxDecoration`에 `borderRadius`가 있으면 `Border`는 **균일 색**이어야 한다. 비균일(예: top만 다른 색) + borderRadius는 paint 단계 assertion → 배경은 그려지나 **자식(글자) 페인트가 중단**되어 라벨이 통째로 사라진다. pill 라벨은 주(week) 칸을 넘어 글자가 이어 흐르도록 `_computeReflowLabels`에서 TextPainter로 미리 측정해 나눠 그린다. (`TextDirection`은 intl과 충돌하므로 `ui.TextDirection` 사용.)
- Hosting은 `no-cache` 헤더 강제(Flutter Web `main.dart.js`에 해시가 없어 immutable 위험 회피) — `firebase.json`.
- 앱은 `firebase_options.dart`로 **항상 운영 Firebase**에 붙는다(앱 자체엔 emulator 배선 없음). 즉 `localhost:5000` 디버그도 **운영 데이터**를 본다.
