# SolenStay 수동 셋업 가이드 (Phase 2)

> Firebase Console에서 클릭만으로 진행. CLI/PowerShell 불필요.
> 예상 소요: 30분~1시간

---

## ✅ Step 1. Firebase 프로젝트 생성

1. **https://console.firebase.google.com** 접속 → Google 로그인
2. **"프로젝트 추가"** 클릭
3. **프로젝트 이름**: `SolenStay`
4. **프로젝트 ID**: 자동 생성된 ID 그대로 사용 (예: `solenstay-xxxxx`)
   - 마음에 안 들면 옆 ✏️ 클릭해서 수정 (전 세계 고유 ID여야 함)
5. **"계속"** 클릭
6. **Google Analytics**: **"이 프로젝트에 Google 애널리틱스 사용 안 함"** 선택
7. **"프로젝트 만들기"** → 1~2분 대기 → **"계속"**

📌 **확인**: 화면 좌측 상단에 "SolenStay" 표시 + 프로젝트 ID 확인 (예: `solenstay-12345`)

---

## ✅ Step 2. Blaze 플랜 활성화

> ⚠ Cloud Functions의 외부 HTTP 호출(iCal fetch)을 하려면 무료 Spark 플랜으로는 불가능. Blaze(종량제)지만 6명 규모면 거의 무료.

1. 좌측 메뉴 **하단**: "Spark 요금제" 옆 **"업그레이드"** 클릭
2. **Blaze 선택**
3. 결제 카드 등록
4. **예산 알림** 설정 권장:
   - 알림 임계값: **$5/월** (이걸 넘으면 알림 받음)
   - 6명 운영 기준 실제 비용: 보통 $0~$1/월

📌 **확인**: 좌측 메뉴 하단에 "Blaze" 표시

---

## ✅ Step 3. Web 앱 등록 (firebaseConfig 발급)

1. 프로젝트 홈(개요) 화면에서 **`</>` 웹 아이콘** 클릭
2. **앱 닉네임**: `SolenStay Web`
3. **"Firebase Hosting도 설정"** 체크 ✅
4. **"앱 등록"** 클릭
5. 다음 화면에 표시되는 **`firebaseConfig` 코드**를 메모장에 복사 저장
   ```js
   const firebaseConfig = {
     apiKey: "...",
     authDomain: "solenstay-xxxxx.firebaseapp.com",
     projectId: "solenstay-xxxxx",
     storageBucket: "solenstay-xxxxx.appspot.com",
     messagingSenderId: "...",
     appId: "..."
   };
   ```
6. **"콘솔로 이동"** 클릭 (Hosting/CLI 안내는 일단 스킵)

📌 **확인**: firebaseConfig 6개 값(특히 `projectId`, `appId`) 메모장에 저장됨

---

## ✅ Step 4. Authentication 활성화

> PIN+이름 로그인은 Custom Token 방식. Authentication 서비스 자체만 활성화하면 됨.

1. 좌측 메뉴 **"Build" → "Authentication"** 클릭
2. **"시작하기"** 클릭
3. **"Sign-in method"** 탭으로 이동
4. 어떤 제공업체도 활성화 불필요 (Custom Token은 별도 메뉴 없음, Functions 배포 후 자동)
5. **그냥 뒤로 나오면 됨**

📌 **확인**: "Authentication" 메뉴 클릭 시 "사용자" 탭이 보이면 활성화 완료

---

## ✅ Step 5. Firestore Database 생성

1. 좌측 메뉴 **"Build" → "Firestore Database"** 클릭
2. **"데이터베이스 만들기"** 클릭
3. **위치**: `asia-northeast3 (서울)` 선택 ⚠ 한 번 정하면 변경 불가
4. **"프로덕션 모드로 시작"** 선택
5. **"만들기"** 클릭 → 30초 대기

### 5-1. 보안 룰 입력

1. 상단 **"규칙"** 탭 클릭
2. 기존 룰 전체 삭제 후 아래 내용 붙여넣기:
   ```js
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       // 헬퍼: 인증 + 역할 확인
       function isAuth() { return request.auth != null; }
       function role() { return request.auth.token.role; }
       function isManager() { return isAuth() && role() == 'manager'; }
       function isChiefOrManager() { return isAuth() && (role() == 'chief' || role() == 'manager'); }

       // branches: 인증된 사용자 read · manager만 write
       match /branches/{branchId} {
         allow read: if isAuth();
         allow write: if isManager();
       }

       // users: 본인 또는 manager가 read · manager만 write
       match /users/{uid} {
         allow read: if isAuth() && (request.auth.uid == uid || isManager());
         allow update: if isAuth() && request.auth.uid == uid &&
                          request.resource.data.diff(resource.data).affectedKeys()
                          .hasOnly(['pinHash', 'pinSalt', 'pinChanged', 'fcmTokens']);
         allow create, delete: if isManager();
       }

       // reservations: read all auth · write Functions only (admin SDK 우회)
       match /reservations/{id} {
         allow read: if isAuth();
         allow write: if false;
       }

       // cleanings: read all auth · 본인 참석/완료 또는 chief/manager 강제 할당
       match /cleanings/{id} {
         allow read: if isAuth();
         allow update: if isAuth() && (
           request.auth.uid == request.resource.data.assigneeUid ||
           request.auth.uid == resource.data.assigneeUid ||
           isChiefOrManager()
         );
         allow create, delete: if false; // Functions only
       }

       // checklistTemplates: read all auth · manager만 write
       match /checklistTemplates/{branchId} {
         allow read: if isAuth();
         allow write: if isManager();
       }

       // notifications: 본인 수신분만 read · Functions만 write
       match /notifications/{id} {
         allow read: if isAuth() && request.auth.uid in resource.data.recipientUids;
         allow write: if false;
       }
     }
   }
   ```
3. **"게시"** 클릭

### 5-2. 시드 데이터 입력 (branches 3개)

상단 **"데이터"** 탭 → **"컬렉션 시작"** 클릭

**컬렉션 1: `branches`**

1. 컬렉션 ID: `branches` → 다음
2. 첫 문서:
   - 문서 ID: `branch1`
   - 필드 추가:
     | 필드 | 타입 | 값 |
     |---|---|---|
     | name | string | `1호점` |
     | rooms | number | `4` |
     | maxOccupancy | number | `10` |
     | color | string | `#3B82F6` |
     | iCalSourceUrl | string | (빈 문자열) |
     | active | boolean | `true` |
     | createdAt | timestamp | (지금 시각) |
3. 저장

같은 방식으로 `branch2`, `branch3` 추가:

**branch2**
| 필드 | 타입 | 값 |
|---|---|---|
| name | string | `2호점` |
| rooms | number | `3` |
| maxOccupancy | number | `8` |
| color | string | `#10B981` |
| iCalSourceUrl | string | (빈 문자열) |
| active | boolean | `true` |
| createdAt | timestamp | (지금 시각) |

**branch3**
| 필드 | 타입 | 값 |
|---|---|---|
| name | string | `3호점` |
| rooms | number | `3` |
| maxOccupancy | number | `8` |
| color | string | `#F97316` |
| iCalSourceUrl | string | (빈 문자열) |
| active | boolean | `true` |
| createdAt | timestamp | (지금 시각) |

### 5-3. 체크리스트 템플릿 (`checklistTemplates`)

세 호점 모두 동일한 체크리스트로 시작.

**문서 ID: `branch1` (호점 ID와 동일)**
- 필드: `items` (타입 `array` → 각 항목은 map)
- items 배열 안에 9개 map 추가:

| category | text |
|---|---|
| 침구 & 베드룸 | 시트·베개커버 교체 |
| 침구 & 베드룸 | 이불 정리 및 교체 |
| 침구 & 베드룸 | 침대 밑 청소기 |
| 욕실 | 변기·세면대 소독 |
| 욕실 | 샤워부스 물때 제거 |
| 욕실 | 수건 4장 비치 |
| 어메니티 | 커피·티백 보충 |
| 어메니티 | 샴푸·바디워시 보충 |
| 어메니티 | 생수 2병 비치 |

- 그리고 `updatedAt` (timestamp) 필드 추가

**같은 내용으로 `branch2`, `branch3` 문서도 생성**
(또는 Console에서 우클릭 "복제" 후 ID만 변경)

> 💡 매니저는 추후 ⑦ 관리자 페이지에서 호점별로 다르게 편집 가능

📌 **확인**: Firestore에 `branches`(3) + `checklistTemplates`(3) 컬렉션 보임

---

## ✅ Step 6. Storage 활성화 + 룰

1. 좌측 메뉴 **"Build" → "Storage"** 클릭
2. **"시작하기"** 클릭
3. **"프로덕션 모드로 시작"** 선택 → 다음
4. **위치**: `asia-northeast3` 선택 (Firestore와 동일) → 완료

### 6-1. Storage 보안 룰

1. 상단 **"Rules"** 탭 클릭
2. 기존 룰 삭제 후 아래 붙여넣기:
   ```
   rules_version = '2';
   service firebase.storage {
     match /b/{bucket}/o {
       // 청소 사진: cleanings/{cleaningId}/{filename}
       match /cleanings/{cleaningId}/{photo} {
         allow read: if request.auth != null;
         // 업로드는 5MB 이하 이미지만, 본인 청소 작업만
         allow write: if request.auth != null
                       && request.resource.size < 5 * 1024 * 1024
                       && request.resource.contentType.matches('image/.*');
       }
     }
   }
   ```
   > ⚠ "본인 청소 작업만 업로드" 엄밀 검증은 Cloud Functions에서 처리 (Storage 룰만으로는 cleanings 컬렉션 조회 불가)
3. **"게시"** 클릭

📌 **확인**: Storage 메뉴에 빈 버킷이 보이고 Rules 탭에 위 내용이 적용됨

---

## 🛑 여기까지가 Console 수동 셋업 한계

다음 항목은 **Cloud Functions 코드 작성·배포**가 필요해서 콘솔만으로는 불가:
- 매니저 김성호 계정 시드 (Custom Token + PIN hash)
- iCal 동기화 함수
- 청소원 참석/완료 함수
- 알림 함수
- 사진 자동 삭제 함수

이 단계는 **Phase 3**에서:
- **옵션 A**: Google Cloud Shell (브라우저 안 터미널, Firebase CLI 자동 로그인)
- **옵션 B**: GitHub Actions 자동 배포 (코드 push만 하면 자동)

중 하나로 진행합니다.

---

## ✅ Step 7. 진행 후 알려주세요

다음 정보가 필요합니다:

1. **프로젝트 ID** (예: `solenstay-12345`)
2. **firebaseConfig** 6개 값 (특히 `apiKey`, `appId`)
3. Steps 1~6 중 막힌 단계가 있다면 어디서

이 정보 받으면:
- `BACKEND_DESIGN.md`에 실제 프로젝트 ID 반영
- Cloud Functions 코드(TypeScript) 작성 시작
- 배포 방법(Cloud Shell vs GitHub Actions) 안내

---

## 📌 참고 화면 위치

| 작업 | Console 메뉴 |
|---|---|
| 프로젝트 설정 | ⚙ (좌상단) → "프로젝트 설정" |
| 결제/요금제 | 좌측 메뉴 하단 "사용량 및 결제" |
| 사용자 보기 | Build → Authentication → Users 탭 |
| 데이터 추가 | Build → Firestore Database → Data 탭 |
| 보안 룰 | Firestore Database → Rules 탭 / Storage → Rules 탭 |
| 함수 로그 | Build → Functions → Logs (나중에 배포 후) |
