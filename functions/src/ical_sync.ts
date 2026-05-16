/**
 * iCal 동기화 함수
 *
 * 흐름:
 *   OTA(Airbnb/Booking) iCal → Google Calendar (매니저가 사전 셋업)
 *   → Google Calendar 통합 iCal URL (각 호점)
 *   → 이 Function이 1분 주기로 fetch
 *   → reservations 컬렉션 갱신 (신규는 onReservationCreated 트리거)
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as admin from 'firebase-admin';
import * as ical from 'node-ical';
import { REGION, TIMEZONE, ICAL_SYNC_INTERVAL_MIN } from './lib/constants';
import { requireChiefOrManager } from './lib/helpers';

interface BranchDoc {
  name: string;
  iCalSourceUrl: string;
  active: boolean;
}

/** iCal SUMMARY/DESCRIPTION에서 OTA 추정 */
function detectOTA(summary: string, description: string): 'airbnb' | 'booking' | 'direct' | 'unknown' {
  const text = `${summary} ${description}`.toLowerCase();
  if (text.includes('airbnb')) return 'airbnb';
  if (text.includes('booking')) return 'booking';
  if (text.includes('direct') || text.includes('직접')) return 'direct';
  return 'unknown';
}

/** SUMMARY에서 게스트 이름 추출 시도 */
function extractGuestName(summary: string): string {
  // Airbnb 형식: "Reserved - Guest Name" 또는 "Name (HMxxxxx)"
  const airbnbMatch = summary.match(/(?:Reserved\s*[-–]\s*)?(.+?)(?:\s*\(HM\w+\))?$/i);
  if (airbnbMatch && airbnbMatch[1]) {
    return airbnbMatch[1].trim();
  }
  return summary.trim() || '게스트';
}

/** DESCRIPTION에서 인원수 파싱 시도 (없으면 0) */
function extractGuestCount(description: string): number {
  const match = description.match(/(\d+)\s*(인|명|guests?|adults?)/i);
  return match ? parseInt(match[1], 10) : 0;
}

/** 호점 한 곳의 iCal 동기화 */
async function syncBranch(branchId: string, branch: BranchDoc): Promise<{ added: number; updated: number; total: number }> {
  if (!branch.iCalSourceUrl) {
    console.log(`[skip] ${branchId} ${branch.name}: iCalSourceUrl 미설정`);
    return { added: 0, updated: 0, total: 0 };
  }

  const db = admin.firestore();
  const data = await ical.async.fromURL(branch.iCalSourceUrl);

  let added = 0;
  let updated = 0;
  let total = 0;

  const batch = db.batch();

  for (const key in data) {
    const event = data[key];
    if (event.type !== 'VEVENT') continue;
    total++;

    const iCalUid = event.uid;
    if (!iCalUid) continue;

    const summary = (event.summary as string) || '';
    const description = (event.description as string) || '';
    const start = event.start as Date;
    const end = event.end as Date;

    if (!start || !end) continue;

    const docId = `${branchId}_${iCalUid}`.replace(/[/.#$\[\]]/g, '_');
    const ref = db.collection('reservations').doc(docId);
    const existing = await ref.get();

    const payload = {
      branchId,
      ota: detectOTA(summary, description),
      guestName: extractGuestName(summary),
      guestCount: extractGuestCount(description),
      checkIn: admin.firestore.Timestamp.fromDate(start),
      checkOut: admin.firestore.Timestamp.fromDate(end),
      iCalUid,
      rawSummary: summary,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (!existing.exists) {
      batch.set(ref, {
        ...payload,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      added++;
    } else {
      // 체크인/아웃 또는 게스트 정보 변경 시에만 업데이트
      const prev = existing.data()!;
      const changed =
        prev.checkIn.toDate().getTime() !== start.getTime() ||
        prev.checkOut.toDate().getTime() !== end.getTime() ||
        prev.guestName !== payload.guestName;
      if (changed) {
        batch.update(ref, payload);
        updated++;
      }
    }
  }

  await batch.commit();

  // 호점 lastSyncAt 업데이트
  await db.collection('branches').doc(branchId).update({
    iCalLastSyncAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.log(`[sync] ${branchId} ${branch.name}: total=${total}, added=${added}, updated=${updated}`);
  return { added, updated, total };
}

/**
 * Scheduled: 1분마다 모든 활성 호점의 iCal 동기화
 */
export const syncICalScheduled = onSchedule(
  {
    region: REGION,
    schedule: `every ${ICAL_SYNC_INTERVAL_MIN} minutes`,
    timeZone: TIMEZONE,
    timeoutSeconds: 540,
    memory: '512MiB',
  },
  async () => {
    const db = admin.firestore();
    const snap = await db.collection('branches').where('active', '==', true).get();

    const results: Record<string, unknown> = {};
    for (const doc of snap.docs) {
      const branch = doc.data() as BranchDoc;
      try {
        results[doc.id] = await syncBranch(doc.id, branch);
      } catch (err) {
        console.error(`[sync error] ${doc.id} ${branch.name}:`, err);
        results[doc.id] = { error: String(err) };
      }
    }
    console.log('[syncICalScheduled] done', results);
  },
);

/**
 * onCall: 매니저/실장이 즉시 동기화 트리거
 * @param data { branchId?: string } — 없으면 전체 호점
 */
export const syncICalManual = onCall({ region: REGION, timeoutSeconds: 300 }, async (req) => {
  requireChiefOrManager(req);

  const { branchId } = req.data ?? {};
  const db = admin.firestore();

  if (branchId) {
    const doc = await db.collection('branches').doc(branchId).get();
    if (!doc.exists) {
      throw new HttpsError('not-found', `branch ${branchId} not found`);
    }
    const result = await syncBranch(branchId, doc.data() as BranchDoc);
    return { [branchId]: result };
  }

  const snap = await db.collection('branches').where('active', '==', true).get();
  const results: Record<string, unknown> = {};
  for (const doc of snap.docs) {
    results[doc.id] = await syncBranch(doc.id, doc.data() as BranchDoc);
  }
  return results;
});
