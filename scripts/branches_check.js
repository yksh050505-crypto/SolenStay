/**
 * 진단용(읽기 전용): branches 컬렉션 전체 출력
 * 실행: cd scripts && node branches_check.js
 * 인증: Application Default Credentials
 */
const admin = require('firebase-admin');
const PROJECT_ID = 'solenstay-74f8e';
admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

(async () => {
  try {
    const snap = await db.collection('branches').get();
    console.log(`branches 문서 수: ${snap.size}`);
    snap.forEach((doc) => {
      const d = doc.data();
      console.log('----');
      console.log(`id: ${doc.id}`);
      console.log(`  name: ${d.name}`);
      console.log(`  active: ${d.active}`);
      console.log(`  rooms: ${d.rooms}, maxOccupancy: ${d.maxOccupancy}`);
      console.log(`  color: ${d.color}`);
      const url = d.iCalSourceUrl || '';
      console.log(`  iCalSourceUrl: ${url ? url.slice(0, 80) + (url.length > 80 ? '…' : '') : '(없음)'}`);
      console.log(`  iCalLastSyncAt: ${d.iCalLastSyncAt ? d.iCalLastSyncAt.toDate().toISOString() : '(동기화 기록 없음)'}`);
    });
    // 최근 reservations 호점별 카운트
    const resSnap = await db.collection('reservations').get();
    const byBranch = {};
    resSnap.forEach((doc) => {
      const b = doc.data().branchId || '(없음)';
      byBranch[b] = (byBranch[b] || 0) + 1;
    });
    console.log('==== reservations 호점별 카운트 ====');
    console.log(JSON.stringify(byBranch, null, 2));
    process.exit(0);
  } catch (err) {
    console.error('실패:', err.message);
    process.exit(1);
  }
})();
