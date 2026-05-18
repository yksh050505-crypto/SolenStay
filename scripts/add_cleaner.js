/**
 * 청소원(에블린) 계정 추가 스크립트
 *
 * 실행: cd scripts && node add_cleaner.js
 * 인증: Application Default Credentials (gcloud auth application-default login)
 *
 * 생성 내용:
 *   - Auth: 새 user (displayName: "에블린")
 *   - users/<uid>: role=cleaner, PIN=000000, pinChanged=false, active=true
 *   - Custom Claims: { role: 'cleaner' }
 */
const admin = require('firebase-admin');
const crypto = require('crypto');

const PROJECT_ID = 'solenstay-74f8e';
const NAME = '에블린';
const ROLE = 'cleaner';
const INITIAL_PIN = '000000';

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();
const auth = admin.auth();

function hashPin(pin, salt) {
  return crypto.createHmac('sha256', salt).update(pin).digest('hex');
}

(async () => {
  console.log(`청소원 ${NAME} 계정 생성 시작...`);
  try {
    // 이미 같은 이름이 있는지 확인
    const existing = await db
      .collection('users')
      .where('name', '==', NAME)
      .where('role', '==', ROLE)
      .limit(1)
      .get();

    if (!existing.empty) {
      const doc = existing.docs[0];
      console.log(`⏭ 이미 존재함 — users/${doc.id} (${NAME}, role=${ROLE})`);
      process.exit(0);
    }

    const salt = crypto.randomBytes(16).toString('hex');
    const userRecord = await auth.createUser({ displayName: NAME });
    await auth.setCustomUserClaims(userRecord.uid, { role: ROLE });
    await db.collection('users').doc(userRecord.uid).set({
      name: NAME,
      role: ROLE,
      pinHash: hashPin(INITIAL_PIN, salt),
      pinSalt: salt,
      pinChanged: false,
      fcmTokens: [],
      active: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`✅ 생성 완료!`);
    console.log(`   uid: ${userRecord.uid}`);
    console.log(`   이름: ${NAME}`);
    console.log(`   역할: ${ROLE} (청소원)`);
    console.log(`   초기 PIN: ${INITIAL_PIN}`);
    console.log(`   ⚠ 첫 로그인 후 PIN 변경 필요`);
    process.exit(0);
  } catch (err) {
    console.error('❌ 실패:', err.message);
    console.error(err);
    process.exit(1);
  }
})();
