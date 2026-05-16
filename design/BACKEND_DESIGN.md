# SolenStay 백엔드 설계 (v0.2)

> Flutter Web + Firebase (Auth · Firestore · Storage · Functions · FCM · Hosting)
> 작성일: 2026-05-16
> **Firebase 프로젝트 ID**: `solenstay-f4817`
> **리전**: `asia-northeast3` (Functions/Firestore/Storage 모두)

---

## 1. 비즈니스 요구사항

### 호점 구성
| 호점 | 방 수 | 최대 수용 |
|---|---|---|
| 1호점 | 4 | 10명 |
| 2호점 | 3 | 8명 |
| 3호점 | 3 | 8명 |

### 직위/권한
| 직위 | 주요 권한 |
|---|---|
| 매니저 (사장) — **김성호** | 모든 권한 (관리자 페이지 ⑦ 포함) |
| 청소실장 | 매니저 대시보드 일부(특이사항·미지정 청소) + 청소원 강제 할당. PIN 발급·체크리스트 편집 불가 |
| 청소원 | 자기 청소 작업만, 참석 의사 표시, 완료 보고 |

### 운영 정책
| 항목 | 값 |
|---|---|
| iCal 동기화 주기 | **1분** (Cloud Functions Scheduled, Google Calendar 캐시 한계상 그 이상 빠르게는 무의미) |
| 미참석 알림 시점 | 체크아웃 4시간 전 |
| 미참석 알림 검사 주기 | 1시간 |
| 사진 보존 기간 | **최대 30일** (이후 자동 삭제) |
| 타임존 | Asia/Seoul |

### 청소 흐름
```
OTA(Airbnb/Booking) iCal
  → Google Calendar (매니저가 사전 설정)
  → 앱(Cloud Functions, 15분 주기 동기화)
  → 예약 기반 청소 일정 자동 생성
  → 청소원이 앱에서 "참석" 클릭 (1명 선착순, 취소 가능)
  → 미참석 시 체크아웃 4시간 전 자동 푸시
```

---

## 2. Firestore 데이터 모델

### 컬렉션 구조

#### `branches/{branchId}`
호점 정보. 매니저만 편집.
```ts
{
  name: string;           // "1호점"
  rooms: number;          // 4
  maxOccupancy: number;   // 10
  color: string;          // "#3B82F6"
  iCalSourceUrl: string;  // Google Calendar 통합 iCal URL
  iCalLastSyncAt: Timestamp;
  active: boolean;
  createdAt: Timestamp;
}
```
*문서 ID 예: `branch1`, `branch2`, `branch3`*

#### `users/{uid}`
사용자(매니저·청소실장·청소원).
```ts
{
  name: string;           // "김지영"
  role: 'manager' | 'chief' | 'cleaner';
  pinHash: string;        // HMAC-SHA256(pin, salt)
  pinSalt: string;        // 16바이트 hex
  pinChanged: boolean;    // 초기 000000에서 변경했는지
  fcmTokens: string[];    // 푸시용 (여러 기기)
  active: boolean;
  createdAt: Timestamp;
}
```
*uid는 Firebase Auth가 생성*

#### `reservations/{reservationId}`
OTA 예약. Cloud Functions가 iCal 파싱 후 자동 생성/갱신.
```ts
{
  branchId: string;       // "branch1"
  ota: 'airbnb' | 'booking' | 'direct' | 'unknown';
  guestName: string;      // iCal SUMMARY에서 추출
  guestCount: number;     // iCal DESCRIPTION 파싱 시도 (없으면 0)
  checkIn: Timestamp;
  checkOut: Timestamp;
  iCalUid: string;        // 중복 방지용 unique key
  rawSummary: string;     // 원본 SUMMARY (디버깅용)
  createdAt: Timestamp;
  updatedAt: Timestamp;
}
```

#### `cleanings/{cleaningId}`
청소 작업. Cloud Functions가 reservation의 체크아웃 기반으로 자동 생성.
```ts
{
  branchId: string;
  reservationId: string;     // 연결된 예약
  scheduledDate: Timestamp;  // 체크아웃 = 청소 날짜
  assigneeUid: string | null; // 참석한 청소원 uid (선착순)
  assignedAt: Timestamp | null;
  status: 'unassigned' | 'assigned' | 'in_progress' | 'completed';
  checklist: ChecklistItem[]; // 호점 기본 체크리스트 복사본
  startedAt: Timestamp | null;
  completedAt: Timestamp | null;
  photoUrls: string[];        // Firebase Storage 경로
  memo: string;              // 특이사항
  forceAssigned: boolean;    // 매니저/실장이 강제 할당했는지
  reminderSent: boolean;     // 4시간 전 알림 발송 여부
  createdAt: Timestamp;
}

type ChecklistItem = {
  category: string;  // "침구 & 베드룸"
  text: string;      // "시트·베개커버 교체"
  checked: boolean;
};
```

#### `checklistTemplates/{branchId}`
호점별 기본 체크리스트. 매니저만 편집.
```ts
{
  branchId: string;
  items: ChecklistItem[];  // 카테고리 + 항목들
  updatedAt: Timestamp;
}
```

#### `notifications/{notificationId}`
알림 발송 이력 (감사 추적).
```ts
{
  type: 'new_reservation' | 'unassigned_reminder' | 'cleaning_completed';
  recipientUids: string[];
  payload: object;
  sentAt: Timestamp;
}
```

---

## 3. 보안 룰 (요약)

### `firestore.rules` 핵심
- **branches**: read all authenticated · write manager only
- **users**: read self + manager · write manager only (PIN 발급)
- **reservations**: read all authenticated · write Cloud Functions only
- **cleanings**:
  - read all authenticated
  - update: 본인이 참석/완료 (필드 제한) · 매니저/실장은 강제 할당 가능
- **checklistTemplates**: read all · write manager only

### `storage.rules` 핵심
- `cleanings/{cleaningId}/{photo}`: 해당 cleaning의 assigneeUid만 write · 모두 read

---

## 4. Cloud Functions 명세

### 4-1. 인증
| 함수 | 트리거 | 역할 |
|---|---|---|
| `signInWithPin` | onCall | 이름+PIN → Custom Token 발급 |
| `changePin` | onCall | 본인 PIN 변경 (초기 000000 → 새 PIN) |
| `registerUser` | onCall (manager only) | 신규 사용자 등록 |
| `updateUserPin` | onCall (manager only) | 사용자 PIN 강제 변경 |
| `deactivateUser` | onCall (manager only) | 사용자 비활성화 |

### 4-2. iCal 동기화
| 함수 | 트리거 | 역할 |
|---|---|---|
| `syncICalScheduled` | Scheduled (**1분 주기**) | 모든 활성 호점의 iCal fetch → reservations 갱신 |
| `syncICalManual` | onCall (manager/chief) | 매니저가 즉시 동기화 트리거 |

### 4-3. 청소 일정
| 함수 | 트리거 | 역할 |
|---|---|---|
| `onReservationCreated` | Firestore onCreate (reservations) | 새 예약 발생 시 cleaning 자동 생성 |
| `claimCleaning` | onCall | 청소원이 "참석" 클릭 (선착순) |
| `releaseCleaning` | onCall | 청소원이 참석 취소 |
| `forceAssignCleaning` | onCall (manager/chief) | 강제 할당 |
| `completeCleaning` | onCall | 청소원이 완료 보고 (사진·메모 첨부) |

### 4-4. 알림
| 함수 | 트리거 | 역할 |
|---|---|---|
| `notifyUnassignedReminder` | Scheduled (1시간 주기) | 체크아웃 4시간 전 미지정 청소 → 전체 청소원 + 매니저에게 푸시 |
| `notifyNewReservation` | Firestore onCreate (reservations) | 새 예약 → 청소원들에게 푸시 (옵션) |
| `registerFcmToken` | onCall | 기기 FCM 토큰 등록 |
| `unregisterFcmToken` | onCall | 토큰 해제 (로그아웃 시) |

### 4-5. 유지보수
| 함수 | 트리거 | 역할 |
|---|---|---|
| `cleanupOldPhotos` | Scheduled (매일 03:00 KST) | 30일 이상 된 청소 사진 Storage에서 삭제 + cleanings.photoUrls 정리 |

---

## 5. 사용자 시나리오

### 시나리오 A: 청소원 일상 흐름
1. PWA 앱 실행 → ① PIN 로그인
2. ② 오늘의 청소 화면에서 자신이 참석한 작업 확인 → 미참석 작업도 노출
3. ③ 작업 상세 → 체크리스트 모두 체크 → "다음" 버튼
4. ④ 완료 보고 → 사진 첨부 + 메모 → "완료 처리하기"
5. ⑤ 캘린더에서 앞으로 일정 확인 → 원하는 청소에 "참석" 클릭

### 시나리오 B: 매니저 일상 흐름
1. ⑦ 매니저 대시보드 진입
2. KPI 확인 (오늘 체크아웃/체크인/완료/미지정)
3. **특이사항** 섹션에서 시설 수리 필요 항목 확인
4. **미지정 청소** 섹션에서 빨간 항목 → 청소원에게 강제 할당

### 시나리오 C: iCal 동기화
1. 매니저가 사전에 OTA(Airbnb·Booking) iCal URL을 Google Calendar에 등록 (수동)
2. Google Calendar 통합 iCal URL을 매니저가 branches 문서에 입력
3. Cloud Functions `syncICalScheduled`가 15분마다 fetch
4. 신규 예약 발견 시 reservations 문서 생성 + `onReservationCreated` 트리거
5. cleaning 문서 자동 생성 (status: `unassigned`)
6. 청소원들에게 푸시 (옵션)

### 시나리오 D: 미지정 알림
1. `notifyUnassignedReminder`가 매 1시간 실행
2. `cleanings.where(status == 'unassigned' && scheduledDate <= now + 4h)` 쿼리
3. 매칭된 cleaning에 대해 모든 청소원 + 매니저에게 푸시
4. cleaning.reminderSent = true 마킹 (중복 방지)

---

## 6. 화면 ↔ 데이터 매핑

| 화면 | 읽는 컬렉션 | 쓰는 컬렉션 |
|---|---|---|
| ① 로그인 | (Cloud Function `signInWithPin`) | - |
| ② 오늘의 청소 | `cleanings` (where today, where assigneeUid == self OR status == unassigned) | - |
| ③ 작업 상세 | `cleanings/{id}` | `cleanings/{id}.checklist` (체크 상태) |
| ④ 완료 보고 | `cleanings/{id}` | `cleanings/{id}` (photoUrls, memo, status=completed), Storage 업로드 |
| ⑤ 캘린더 | `reservations`, `cleanings` (앞으로 1개월) | `cleanings/{id}` (claim/release) |
| ⑥ 내정보 | `users/{self}` | `users/{self}.pinHash` (PIN 변경), `users/{self}.fcmTokens` |
| ⑦ 매니저 대시보드 | `cleanings`, `reservations`, `users` (집계 쿼리) | `cleanings/{id}.assigneeUid` (강제 할당) |

---

## 7. 초기 시드 데이터

### branches
```js
{ id: "branch1", name: "1호점", rooms: 4, maxOccupancy: 10, color: "#3B82F6", iCalSourceUrl: "", active: true }
{ id: "branch2", name: "2호점", rooms: 3, maxOccupancy: 8,  color: "#10B981", iCalSourceUrl: "", active: true }
{ id: "branch3", name: "3호점", rooms: 3, maxOccupancy: 8,  color: "#F97316", iCalSourceUrl: "", active: true }
```

### checklistTemplates (호점별 동일하게 시작)
```js
{
  items: [
    { category: "침구 & 베드룸", text: "시트·베개커버 교체" },
    { category: "침구 & 베드룸", text: "이불 정리 및 교체" },
    { category: "침구 & 베드룸", text: "침대 밑 청소기" },
    { category: "욕실", text: "변기·세면대 소독" },
    { category: "욕실", text: "샤워부스 물때 제거" },
    { category: "욕실", text: "수건 4장 비치" },
    { category: "어메니티", text: "커피·티백 보충" },
    { category: "어메니티", text: "샴푸·바디워시 보충" },
    { category: "어메니티", text: "생수 2병 비치" }
  ]
}
```

### users (시드 스크립트로 매니저 1명 생성)
```js
{ name: "김성호", role: "manager", pin: "000000" }
// → registerUser Function이 hashPin + pinChanged: false로 저장
// 김성호가 첫 로그인 후 PIN 변경 + 청소실장/청소원 직접 등록
```

---

## 8. 결정 항목 (확정/추후)

### ✅ 확정
- **매니저 이름**: 김성호
- **사진 보존 기간**: 30일 (이후 `cleanupOldPhotos` Function이 자동 삭제)
- **iCal 동기화 주기**: 1분
- **타임존**: Asia/Seoul
- **알림 시점**: 체크아웃 4시간 전

### ⏳ 추후 결정 (배포 직전)
- [ ] **OTA iCal URL** — 각 호점 Google Calendar 통합 iCal 주소 (매니저가 사전 셋업 후 입력)
- [ ] **청소실장 1명 + 청소원 명단** — 매니저가 첫 로그인 후 등록
- [ ] **PWA 설치 안내 문구** — 청소원에게 첫 로그인 시 홈화면 추가 가이드

---

## 9. 다음 단계

1. 이 설계 문서 검토 + 수정 사항 반영
2. **Node.js LTS + Firebase CLI 설치**
3. Firebase 프로젝트 생성 + 결제 플랜 Blaze 활성화
4. `flutterfire configure` (Flutter 앱 ↔ Firebase 연결)
5. `functions/` 폴더 생성 + TypeScript 셋업
6. 위 명세대로 Cloud Functions 구현 (Phase 3)
