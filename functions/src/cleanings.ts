/**
 * 청소 일정 관리 함수
 *
 * - onReservationCreated: 새 예약 발생 시 청소 작업 자동 생성
 * - claimCleaning: 청소원이 "참석" 클릭 (선착순 1명)
 * - releaseCleaning: 청소원이 참석 취소
 * - forceAssignCleaning: 매니저/실장이 강제 할당
 * - completeCleaning: 청소원이 완료 보고 (사진·메모 첨부 후)
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import * as admin from 'firebase-admin';
import { REGION } from './lib/constants';
import {
  requireAuth,
  requireChiefOrManager,
} from './lib/helpers';

interface ChecklistItem {
  category: string;
  text: string;
  checked?: boolean;
}

/**
 * Firestore 트리거: 새 예약 생성 시 cleanings 문서 자동 생성
 * - scheduledDate = reservation.checkOut (체크아웃일에 청소)
 * - 호점별 checklistTemplates 복사
 */
export const onReservationCreated = onDocumentCreated(
  { region: REGION, document: 'reservations/{reservationId}' },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const reservation = snap.data() as {
      branchId: string;
      checkOut: admin.firestore.Timestamp;
    };

    const db = admin.firestore();

    // 호점 체크리스트 템플릿 조회
    const tplDoc = await db.collection('checklistTemplates').doc(reservation.branchId).get();
    const items: ChecklistItem[] = tplDoc.exists
      ? (tplDoc.data()?.items ?? []).map((i: ChecklistItem) => ({ ...i, checked: false }))
      : [];

    // cleaning 문서 생성 (ID는 reservation ID와 동일하게 → 1:1 매핑)
    await db.collection('cleanings').doc(event.params.reservationId).set({
      branchId: reservation.branchId,
      reservationId: event.params.reservationId,
      scheduledDate: reservation.checkOut,
      assigneeUid: null,
      assignedAt: null,
      status: 'unassigned',
      checklist: items,
      startedAt: null,
      completedAt: null,
      photoUrls: [],
      memo: '',
      forceAssigned: false,
      reminderSent: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log(`[cleaning created] ${event.params.reservationId} for branch ${reservation.branchId}`);
  },
);

/**
 * 청소원이 "참석" 클릭 (선착순 1명)
 * @param data { cleaningId: string }
 */
export const claimCleaning = onCall({ region: REGION }, async (req) => {
  const auth = requireAuth(req);
  const { cleaningId } = req.data ?? {};
  if (typeof cleaningId !== 'string' || !cleaningId) {
    throw new HttpsError('invalid-argument', 'cleaningId required');
  }

  const db = admin.firestore();
  const ref = db.collection('cleanings').doc(cleaningId);

  // 청소원 이름 미리 조회 (denormalize 용)
  const userDoc = await db.collection('users').doc(auth.uid).get();
  const userName = (userDoc.data()?.name as string | undefined) ?? '';

  await db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists) {
      throw new HttpsError('not-found', 'cleaning not found');
    }
    const data = doc.data()!;
    if (data.assigneeUid && data.assigneeUid !== auth.uid) {
      throw new HttpsError('already-exists', '이미 다른 청소원이 참석 중입니다');
    }
    if (data.status === 'completed') {
      throw new HttpsError('failed-precondition', '이미 완료된 청소입니다');
    }
    tx.update(ref, {
      assigneeUid: auth.uid,
      assigneeName: userName,
      assignedAt: admin.firestore.FieldValue.serverTimestamp(),
      status: 'assigned',
      forceAssigned: false,
    });
  });

  return { ok: true };
});

/**
 * 청소원이 참석 취소
 * @param data { cleaningId: string }
 */
export const releaseCleaning = onCall({ region: REGION }, async (req) => {
  const auth = requireAuth(req);
  const { cleaningId } = req.data ?? {};
  if (typeof cleaningId !== 'string') {
    throw new HttpsError('invalid-argument', 'cleaningId required');
  }

  const db = admin.firestore();
  const ref = db.collection('cleanings').doc(cleaningId);

  await db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists) throw new HttpsError('not-found', 'cleaning not found');
    const data = doc.data()!;
    if (data.assigneeUid !== auth.uid) {
      throw new HttpsError('permission-denied', '본인 청소만 취소 가능');
    }
    if (data.status === 'in_progress' || data.status === 'completed') {
      throw new HttpsError('failed-precondition', '진행중/완료 청소는 취소 불가');
    }
    // 체크리스트 초기화 — 다음 담당자가 처음부터 시작하도록
    const resetChecklist = ((data.checklist as Array<{ category: string; text: string; checked?: boolean }> | undefined) ?? [])
      .map((i) => ({ ...i, checked: false }));
    tx.update(ref, {
      assigneeUid: null,
      assigneeName: null,
      assignedAt: null,
      status: 'unassigned',
      checklist: resetChecklist,
    });
  });

  return { ok: true };
});

/**
 * 매니저/실장이 강제 할당
 * @param data { cleaningId: string, uid: string }
 */
export const forceAssignCleaning = onCall({ region: REGION }, async (req) => {
  requireChiefOrManager(req);
  const { cleaningId, uid } = req.data ?? {};
  if (typeof cleaningId !== 'string' || typeof uid !== 'string') {
    throw new HttpsError('invalid-argument', 'cleaningId, uid required');
  }

  const db = admin.firestore();
  const userDoc = await db.collection('users').doc(uid).get();
  if (!userDoc.exists || !userDoc.data()?.active) {
    throw new HttpsError('not-found', '대상 청소원이 존재하지 않거나 비활성');
  }
  const userName = (userDoc.data()?.name as string | undefined) ?? '';

  const ref = db.collection('cleanings').doc(cleaningId);
  const cleaningDoc = await ref.get();
  if (!cleaningDoc.exists) {
    throw new HttpsError('not-found', 'cleaning not found');
  }
  const cleaningData = cleaningDoc.data()!;
  // 다른 담당자로 강제 재할당 시 체크리스트 초기화 (기존 진행 내용 제거)
  const isReassign = cleaningData.assigneeUid && cleaningData.assigneeUid !== uid;
  const updates: Record<string, unknown> = {
    assigneeUid: uid,
    assigneeName: userName,
    assignedAt: admin.firestore.FieldValue.serverTimestamp(),
    status: 'assigned',
    forceAssigned: true,
  };
  if (isReassign) {
    const resetChecklist = ((cleaningData.checklist as Array<{ category: string; text: string; checked?: boolean }> | undefined) ?? [])
      .map((i) => ({ ...i, checked: false }));
    updates.checklist = resetChecklist;
  }

  await ref.update(updates);

  return { ok: true };
});

/**
 * 청소원이 완료 보고
 * @param data { cleaningId: string, checklist: ChecklistItem[], photoUrls: string[], memo?: string }
 */
export const completeCleaning = onCall({ region: REGION }, async (req) => {
  const auth = requireAuth(req);
  const { cleaningId, checklist, photoUrls, memo } = req.data ?? {};

  if (typeof cleaningId !== 'string') {
    throw new HttpsError('invalid-argument', 'cleaningId required');
  }
  if (!Array.isArray(checklist)) {
    throw new HttpsError('invalid-argument', 'checklist must be array');
  }
  if (!Array.isArray(photoUrls)) {
    throw new HttpsError('invalid-argument', 'photoUrls must be array');
  }
  if (photoUrls.length > 12) {
    throw new HttpsError('invalid-argument', '사진은 최대 12장');
  }
  // 모든 체크리스트 항목이 체크되었는지 검증
  const allChecked = checklist.every((i: ChecklistItem) => i.checked === true);
  if (!allChecked) {
    throw new HttpsError('failed-precondition', '체크리스트 모든 항목 체크 필요');
  }

  const db = admin.firestore();
  const ref = db.collection('cleanings').doc(cleaningId);

  // 다음 게스트 스냅샷 — 완료 시점에 1회만 캡처
  const cleaningSnap = await ref.get();
  if (!cleaningSnap.exists) {
    throw new HttpsError('not-found', 'cleaning not found');
  }
  const cleaningData = cleaningSnap.data()!;
  const branchId = cleaningData.branchId as string;
  const scheduledDate = cleaningData.scheduledDate as admin.firestore.Timestamp;

  // checkIn == scheduledDate (같은 날) 인 다른 예약 = 다음 게스트
  const dayStart = new Date(scheduledDate.toDate());
  dayStart.setHours(0, 0, 0, 0);
  const dayEnd = new Date(dayStart);
  dayEnd.setDate(dayEnd.getDate() + 1);

  const nextResSnap = await db
    .collection('reservations')
    .where('branchId', '==', branchId)
    .where('checkIn', '>=', admin.firestore.Timestamp.fromDate(dayStart))
    .where('checkIn', '<', admin.firestore.Timestamp.fromDate(dayEnd))
    .limit(1)
    .get();

  let nextGuestSnapshot: admin.firestore.FieldValue | Record<string, unknown> =
    admin.firestore.FieldValue.delete();
  if (!nextResSnap.empty) {
    const r = nextResSnap.docs[0].data();
    nextGuestSnapshot = {
      reservationId: nextResSnap.docs[0].id,
      guestName: (r.guestName as string) ?? '',
      guestCount: (r.guestCount as number) ?? 0,
      ota: (r.ota as string) ?? 'unknown',
      checkIn: r.checkIn,
      checkOut: r.checkOut,
    };
  }

  await db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists) throw new HttpsError('not-found', 'cleaning not found');
    const data = doc.data()!;
    if (data.assigneeUid !== auth.uid) {
      throw new HttpsError('permission-denied', '본인 청소만 완료 처리 가능');
    }
    if (data.status === 'completed') {
      throw new HttpsError('failed-precondition', '이미 완료된 청소');
    }

    tx.update(ref, {
      checklist,
      photoUrls,
      memo: typeof memo === 'string' ? memo : '',
      status: 'completed',
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      nextGuestSnapshot,
    });
  });

  return { ok: true };
});
