/**
 * 알림 함수
 *
 * - notifyUnassignedReminder: Scheduled (1시간), 체크아웃 4시간 전 미지정 청소 → 청소원·매니저 푸시
 * - notifyNewReservation: Firestore onCreate (reservations) → 청소원에게 새 예약 푸시
 * - registerFcmToken / unregisterFcmToken: 디바이스 토큰 관리
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import * as admin from 'firebase-admin';
import {
  REGION,
  TIMEZONE,
  REMINDER_HOURS_BEFORE_CHECKOUT,
  UNASSIGNED_CHECK_INTERVAL_MIN,
} from './lib/constants';
import { requireAuth } from './lib/helpers';

interface UserDoc {
  name: string;
  role: 'manager' | 'chief' | 'cleaner';
  fcmTokens?: string[];
  active: boolean;
}

/** 특정 역할 사용자들의 FCM 토큰 수집 */
async function collectTokens(roles: Array<'manager' | 'chief' | 'cleaner'>): Promise<{ tokens: string[]; uids: string[] }> {
  const db = admin.firestore();
  const tokens: string[] = [];
  const uids: string[] = [];

  const snap = await db
    .collection('users')
    .where('active', '==', true)
    .where('role', 'in', roles)
    .get();

  for (const doc of snap.docs) {
    const u = doc.data() as UserDoc;
    if (Array.isArray(u.fcmTokens) && u.fcmTokens.length > 0) {
      tokens.push(...u.fcmTokens);
      uids.push(doc.id);
    }
  }

  return { tokens, uids };
}

/** FCM 멀티캐스트 전송 + 무효 토큰 제거 */
async function sendMulticast(
  tokens: string[],
  notification: { title: string; body: string },
  data?: Record<string, string>,
): Promise<{ success: number; failure: number }> {
  if (tokens.length === 0) return { success: 0, failure: 0 };

  const message = {
    tokens,
    notification,
    data: data ?? {},
    webpush: { fcmOptions: { link: '/' } },
  };

  const res = await admin.messaging().sendEachForMulticast(message);

  // 실패한 토큰 정리 (UNREGISTERED, INVALID_ARGUMENT 등)
  if (res.failureCount > 0) {
    const db = admin.firestore();
    const invalidTokens = res.responses
      .map((r, i) => (!r.success ? tokens[i] : null))
      .filter((t): t is string => t !== null);

    if (invalidTokens.length > 0) {
      const usersSnap = await db.collection('users').where('fcmTokens', 'array-contains-any', invalidTokens).get();
      const batch = db.batch();
      for (const userDoc of usersSnap.docs) {
        const remaining = (userDoc.data().fcmTokens as string[]).filter((t) => !invalidTokens.includes(t));
        batch.update(userDoc.ref, { fcmTokens: remaining });
      }
      await batch.commit();
    }
  }

  return { success: res.successCount, failure: res.failureCount };
}

/**
 * Scheduled: 1시간마다 체크아웃 4시간 내 미지정 청소를 찾아 푸시
 */
export const notifyUnassignedReminder = onSchedule(
  {
    region: REGION,
    schedule: `every ${UNASSIGNED_CHECK_INTERVAL_MIN} minutes`,
    timeZone: TIMEZONE,
  },
  async () => {
    const db = admin.firestore();
    const now = Date.now();
    const threshold = now + REMINDER_HOURS_BEFORE_CHECKOUT * 60 * 60 * 1000;

    const snap = await db
      .collection('cleanings')
      .where('status', '==', 'unassigned')
      .where('reminderSent', '==', false)
      .where('scheduledDate', '<=', admin.firestore.Timestamp.fromMillis(threshold))
      .where('scheduledDate', '>=', admin.firestore.Timestamp.fromMillis(now))
      .get();

    if (snap.empty) {
      console.log('[reminder] 미지정 청소 없음');
      return;
    }

    const { tokens, uids } = await collectTokens(['cleaner', 'chief', 'manager']);
    const branchNames = new Map<string, string>();
    const branchesSnap = await db.collection('branches').get();
    branchesSnap.docs.forEach((d) => branchNames.set(d.id, (d.data().name as string) ?? d.id));

    const batch = db.batch();
    for (const doc of snap.docs) {
      const c = doc.data();
      const branchName = branchNames.get(c.branchId) ?? c.branchId;
      const dateStr = (c.scheduledDate as admin.firestore.Timestamp).toDate().toLocaleDateString('ko-KR');

      const result = await sendMulticast(
        tokens,
        {
          title: '⚠ 청소 담당자 미지정',
          body: `${branchName} ${dateStr} 청소가 아직 미지정입니다. 참석해주세요.`,
        },
        { type: 'unassigned_reminder', cleaningId: doc.id, branchId: c.branchId },
      );

      // notifications 이력
      const notifRef = db.collection('notifications').doc();
      batch.set(notifRef, {
        type: 'unassigned_reminder',
        recipientUids: uids,
        payload: { cleaningId: doc.id, branchId: c.branchId, result },
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      batch.update(doc.ref, { reminderSent: true });

      console.log(`[reminder] ${doc.id} → success=${result.success}, failure=${result.failure}`);
    }

    await batch.commit();
  },
);

/**
 * Firestore 트리거: 새 예약 생성 시 청소원에게 푸시
 */
export const notifyNewReservation = onDocumentCreated(
  { region: REGION, document: 'reservations/{reservationId}' },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const r = snap.data() as {
      branchId: string;
      guestName: string;
      guestCount: number;
      checkOut: admin.firestore.Timestamp;
    };

    const db = admin.firestore();
    const branchDoc = await db.collection('branches').doc(r.branchId).get();
    const branchName = (branchDoc.data()?.name as string) ?? r.branchId;
    const dateStr = r.checkOut.toDate().toLocaleDateString('ko-KR');

    const { tokens, uids } = await collectTokens(['cleaner', 'chief']);
    if (tokens.length === 0) return;

    const result = await sendMulticast(
      tokens,
      {
        title: '🆕 새 청소 일정',
        body: `${branchName} ${dateStr} · ${r.guestName} ${r.guestCount > 0 ? `(${r.guestCount}인)` : ''}`,
      },
      { type: 'new_reservation', cleaningId: event.params.reservationId, branchId: r.branchId },
    );

    await db.collection('notifications').add({
      type: 'new_reservation',
      recipientUids: uids,
      payload: { cleaningId: event.params.reservationId, result },
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  },
);

/**
 * FCM 토큰 등록 (디바이스/브라우저 단위)
 * @param data { token: string }
 */
export const registerFcmToken = onCall({ region: REGION }, async (req) => {
  const auth = requireAuth(req);
  const { token } = req.data ?? {};
  if (typeof token !== 'string' || !token) {
    throw new HttpsError('invalid-argument', 'token required');
  }

  await admin.firestore().collection('users').doc(auth.uid).update({
    fcmTokens: admin.firestore.FieldValue.arrayUnion(token),
  });

  return { ok: true };
});

/**
 * FCM 토큰 해제 (로그아웃 시)
 * @param data { token: string }
 */
export const unregisterFcmToken = onCall({ region: REGION }, async (req) => {
  const auth = requireAuth(req);
  const { token } = req.data ?? {};
  if (typeof token !== 'string') {
    throw new HttpsError('invalid-argument', 'token required');
  }

  await admin.firestore().collection('users').doc(auth.uid).update({
    fcmTokens: admin.firestore.FieldValue.arrayRemove(token),
  });

  return { ok: true };
});
