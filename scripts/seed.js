/**
 * SolenStay 초기 시드 스크립트
 *
 * 실행 환경: Cloud Shell (또는 firebase-admin 설치된 어떤 Node.js 환경)
 * 실행 방법:
 *   gcloud config set project solenstay-74f8e
 *   cd scripts && npm install
 *   node seed.js
 *
 * 시드 내용:
 *   1. checklistTemplates × 3 (branch1, branch2, branch3, 공통 항목 9개)
 *   2. 매니저 김성호 계정 (role=manager, PIN=000000, pinChanged=false)
 *
 * 멱등성: 같은 데이터는 덮어쓰기. 매니저 계정은 이미 같은 이름이면 스킵.
 */

const admin = require('firebase-admin');
const crypto = require('crypto');

const PROJECT_ID = 'solenstay-74f8e';
const MANAGER_NAME = '김성호';
const INITIAL_PIN = '000000';

admin.initializeApp({
  projectId: PROJECT_ID,
});

const db = admin.firestore();
const auth = admin.auth();

function hashPin(pin, salt) {
  return crypto.createHmac('sha256', salt).update(pin).digest('hex');
}

const checklistItems = [
  { category: '침구 & 베드룸', text: '시트·베개커버 교체' },
  { category: '침구 & 베드룸', text: '이불 정리 및 교체' },
  { category: '침구 & 베드룸', text: '침대 밑 청소기' },
  { category: '욕실', text: '변기·세면대 소독' },
  { category: '욕실', text: '샤워부스 물때 제거' },
  { category: '욕실', text: '수건 4장 비치' },
  { category: '어메니티', text: '커피·티백 보충' },
  { category: '어메니티', text: '샴푸·바디워시 보충' },
  { category: '어메니티', text: '생수 2병 비치' },
];

async function seedChecklistTemplates() {
  console.log('\n[1/2] checklistTemplates 시드 시작...');
  for (const branchId of ['branch1', 'branch2', 'branch3']) {
    await db.collection('checklistTemplates').doc(branchId).set({
      items: checklistItems,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`  ✅ checklistTemplates/${branchId} — ${checklistItems.length}개 항목`);
  }
}

async function seedManager() {
  console.log('\n[2/2] 매니저 계정 시드 시작...');

  // 이미 같은 이름의 사용자가 있는지 Firestore에서 검색
  const existing = await db
    .collection('users')
    .where('name', '==', MANAGER_NAME)
    .where('role', '==', 'manager')
    .limit(1)
    .get();

  if (!existing.empty) {
    const doc = existing.docs[0];
    console.log(`  ⏭ 이미 존재함 — users/${doc.id} (${MANAGER_NAME}, role=manager)`);
    return;
  }

  const salt = crypto.randomBytes(16).toString('hex');
  const userRecord = await auth.createUser({ displayName: MANAGER_NAME });
  await auth.setCustomUserClaims(userRecord.uid, { role: 'manager' });
  await db.collection('users').doc(userRecord.uid).set({
    name: MANAGER_NAME,
    role: 'manager',
    pinHash: hashPin(INITIAL_PIN, salt),
    pinSalt: salt,
    pinChanged: false,
    fcmTokens: [],
    active: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log(`  ✅ users/${userRecord.uid} — ${MANAGER_NAME}, role=manager, PIN=${INITIAL_PIN}`);
  console.log(`  ⚠ 첫 로그인 후 PIN을 반드시 변경하세요!`);
}

(async () => {
  console.log(`SolenStay 시드 시작 — project: ${PROJECT_ID}`);
  try {
    await seedChecklistTemplates();
    await seedManager();
    console.log('\n✨ 시드 완료!');
    process.exit(0);
  } catch (err) {
    console.error('\n❌ 시드 실패:', err.message);
    console.error(err);
    process.exit(1);
  }
})();
