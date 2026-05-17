/**
 * 오늘 날짜의 테스트 청소 일정 3건 생성 (호점별 1건씩).
 * 실행: cd scripts && node add_test_cleaning.js
 * 인증: Application Default Credentials (gcloud auth application-default login)
 */
const admin = require('firebase-admin');

const PROJECT_ID = 'solenstay-74f8e';

admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

const checklistItems = [
  { category: '침구 & 베드룸', text: '시트·베개커버 교체', checked: false },
  { category: '침구 & 베드룸', text: '이불 정리 및 교체', checked: false },
  { category: '침구 & 베드룸', text: '침대 밑 청소기', checked: false },
  { category: '욕실', text: '변기·세면대 소독', checked: false },
  { category: '욕실', text: '샤워부스 물때 제거', checked: false },
  { category: '욕실', text: '수건 4장 비치', checked: false },
  { category: '어메니티', text: '커피·티백 보충', checked: false },
  { category: '어메니티', text: '샴푸·바디워시 보충', checked: false },
  { category: '어메니티', text: '생수 2병 비치', checked: false },
];

(async () => {
  // 오늘 날짜 — 시간은 오전 11시로 고정
  const now = new Date();
  const scheduled = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 11, 0, 0);

  const cleanings = [
    { branchId: 'branch1', hour: 11 },
    { branchId: 'branch2', hour: 14 },
    { branchId: 'branch3', hour: 16 },
  ];

  for (const c of cleanings) {
    const dt = new Date(now.getFullYear(), now.getMonth(), now.getDate(), c.hour, 0, 0);
    const docRef = await db.collection('cleanings').add({
      branchId: c.branchId,
      reservationId: '',
      scheduledDate: admin.firestore.Timestamp.fromDate(dt),
      assigneeUid: null,
      status: 'unassigned',
      checklist: checklistItems,
      photoUrls: [],
      memo: '',
      completedAt: null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`✅ cleanings/${docRef.id} — ${c.branchId} @ ${dt.toLocaleString('ko-KR')}`);
  }

  console.log('\n✨ 테스트 청소 일정 3건 생성 완료!');
  process.exit(0);
})().catch((err) => {
  console.error('❌ 실패:', err.message);
  process.exit(1);
});
