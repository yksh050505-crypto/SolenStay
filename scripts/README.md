# SolenStay 운영 스크립트

> Cloud Shell에서 실행. 로컬에 Node.js 설치 불필요.

## 🚀 Cloud Shell에서 시드 실행

### 1. Cloud Shell 접속
- https://shell.cloud.google.com 또는 Firebase Console 우측 상단 터미널 아이콘 클릭
- 무료 가상 머신 자동 시작 (10~20초)

### 2. 프로젝트 설정 + 레포 clone
```bash
gcloud config set project solenstay-74f8e
git clone https://github.com/yksh050505-crypto/SolenStay.git
cd SolenStay/scripts
```

### 3. 의존성 설치
```bash
npm install
```

### 4. 시드 실행
```bash
node seed.js
```

### 5. 출력 확인
```
SolenStay 시드 시작 — project: solenstay-74f8e

[1/2] checklistTemplates 시드 시작...
  ✅ checklistTemplates/branch1 — 9개 항목
  ✅ checklistTemplates/branch2 — 9개 항목
  ✅ checklistTemplates/branch3 — 9개 항목

[2/2] 매니저 계정 시드 시작...
  ✅ users/<uid> — 김성호, role=manager, PIN=000000
  ⚠ 첫 로그인 후 PIN을 반드시 변경하세요!

✨ 시드 완료!
```

## 📝 시드 내용

- **checklistTemplates** (3개 문서): 호점별 청소 체크리스트 9개 항목 (침구·욕실·어메니티)
- **매니저 계정**: 김성호 / role=manager / PIN=000000 (Custom Claims `role` 자동 설정)

## ⚠ 주의

- 시드 스크립트는 **멱등성**: 매니저 계정이 이미 같은 이름으로 존재하면 스킵.
- checklistTemplates는 매번 덮어쓰기. 매니저가 콘솔이나 ⑦ 관리자 페이지에서 수정한 경우 주의.
- 시드 후 Firebase Console → Authentication → Users 탭에서 김성호 계정 확인 가능.
