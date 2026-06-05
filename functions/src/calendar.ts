/**
 * 청소원 개인용 iCal 캘린더 구독 endpoint.
 *
 * 흐름:
 *   1) 사용자가 앱에서 `getOrCreateCalendarToken` 호출 → 토큰 발급 (없으면 생성)
 *   2) 발급된 토큰으로 URL 구성: https://....../myCalendar?token=<token>
 *   3) 그 URL을 구글/아이폰 캘린더에 구독 등록
 *   4) 구글/아이폰이 주기적으로 fetch → 자동 동기화
 *
 * 보안:
 *   - 토큰만 알면 그 사용자의 청소 일정 전체가 노출 → 노출 시 `revokeCalendarToken` 으로 갱신
 *   - 토큰은 32바이트 hex (64자) 랜덤
 */

import * as crypto from 'crypto';
import { onCall, onRequest, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { REGION } from './lib/constants';
import { requireAuth } from './lib/helpers';

const db = () => admin.firestore();

// ─────────────────────────────────────────────────────────────
// 토큰 발급 / 재발급 / 해제 (callable)
// ─────────────────────────────────────────────────────────────

/**
 * 본인의 calendarToken을 반환. 없으면 새로 발급.
 * @returns { token: string }
 */
export const getOrCreateCalendarToken = onCall({ region: REGION }, async (req) => {
  const auth = requireAuth(req);
  const uid = auth.uid;
  const ref = db().collection('users').doc(uid);
  const snap = await ref.get();
  const existing = snap.get('calendarToken') as string | undefined;
  if (existing && existing.length === 64) {
    return { token: existing };
  }
  const token = crypto.randomBytes(32).toString('hex'); // 64 chars
  await ref.set({ calendarToken: token }, { merge: true });
  return { token };
});

/**
 * 토큰 재발급 (기존 URL은 그 즉시 무효화됨).
 * @returns { token: string }
 */
export const regenerateCalendarToken = onCall({ region: REGION }, async (req) => {
  const auth = requireAuth(req);
  const uid = auth.uid;
  const token = crypto.randomBytes(32).toString('hex');
  await db().collection('users').doc(uid).set({ calendarToken: token }, { merge: true });
  return { token };
});

/**
 * 토큰 삭제 — 연동 해제. 등록된 캘린더는 다음 fetch 시 404로 빌 거임.
 */
export const revokeCalendarToken = onCall({ region: REGION }, async (req) => {
  const auth = requireAuth(req);
  const uid = auth.uid;
  await db()
    .collection('users')
    .doc(uid)
    .set({ calendarToken: admin.firestore.FieldValue.delete() }, { merge: true });
  return { ok: true };
});

// ─────────────────────────────────────────────────────────────
// HTTP endpoint: 본인 청소 일정을 iCal(.ics) 형식으로 반환
// ─────────────────────────────────────────────────────────────

/** ICS 텍스트 escape (쉼표·세미콜론·백슬래시·개행) */
function icsEscape(s: string): string {
  return s
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\r?\n/g, '\\n');
}

/** YYYYMMDD (UTC 무시, 로컬 날짜 기준 — 종일 이벤트) */
function ymd(d: Date): string {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}${m}${day}`;
}

/** YYYYMMDDTHHmmssZ (UTC) — DTSTAMP용 */
function utcStamp(d: Date): string {
  return `${d.getUTCFullYear()}${String(d.getUTCMonth() + 1).padStart(2, '0')}${String(d.getUTCDate()).padStart(2, '0')}T${String(d.getUTCHours()).padStart(2, '0')}${String(d.getUTCMinutes()).padStart(2, '0')}${String(d.getUTCSeconds()).padStart(2, '0')}Z`;
}

interface CleaningDoc {
  branchId?: string;
  reservationId?: string;
  scheduledDate?: admin.firestore.Timestamp;
  assigneeUid?: string;
  status?: string;
}

interface ReservationDoc {
  branchId?: string;
  guestName?: string;
  guestCount?: number;
}

interface BranchDoc {
  name?: string;
}

/**
 * `GET /myCalendar?token=<token>`
 *   → text/calendar (iCalendar 2.0)
 *   → 본인이 배정된 청소만 (assigneeUid == 본인, status != 'unassigned')
 *   → 종일 이벤트
 *   → 취소/삭제된 청소는 자동으로 빠짐 (응답에서 빠지면 구독자 측에서 자동 제거)
 */
export const myCalendar = onRequest({ region: REGION, cors: false }, async (req, res) => {
  const token = req.query.token as string | undefined;
  if (!token || token.length !== 64) {
    res.status(400).send('invalid token');
    return;
  }
  // 토큰으로 사용자 찾기
  const userSnap = await db()
    .collection('users')
    .where('calendarToken', '==', token)
    .limit(1)
    .get();
  if (userSnap.empty) {
    res.status(404).send('not found');
    return;
  }
  const userDoc = userSnap.docs[0];
  const uid = userDoc.id;
  const userName = (userDoc.get('name') as string | undefined) ?? '';

  // 본인 배정 청소 (미배정 제외) — 최근 30일 ~ 향후 1년
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 30);
  const end = new Date(now.getFullYear() + 1, now.getMonth(), now.getDate());

  const cleaningsSnap = await db()
    .collection('cleanings')
    .where('assigneeUid', '==', uid)
    .where('scheduledDate', '>=', admin.firestore.Timestamp.fromDate(start))
    .where('scheduledDate', '<', admin.firestore.Timestamp.fromDate(end))
    .get();

  // 호점 이름 한번 미리 로드
  const branchSnaps = await db().collection('branches').get();
  const branchNames: Record<string, string> = {};
  branchSnaps.forEach((b) => {
    branchNames[b.id] = (b.data() as BranchDoc).name ?? b.id;
  });

  // 각 청소의 예약 정보(게스트명/인원) 병렬 로드
  const cleaningDocs = cleaningsSnap.docs.filter((d) => {
    const c = d.data() as CleaningDoc;
    return c.status !== 'unassigned' && c.assigneeUid === uid && c.scheduledDate;
  });

  const reservationFetches = cleaningDocs.map(async (d) => {
    const c = d.data() as CleaningDoc;
    if (!c.reservationId) return { d, c, r: undefined as ReservationDoc | undefined };
    const r = await db().collection('reservations').doc(c.reservationId).get();
    return { d, c, r: r.exists ? (r.data() as ReservationDoc) : undefined };
  });
  const items = await Promise.all(reservationFetches);

  const lines: string[] = [];
  lines.push('BEGIN:VCALENDAR');
  lines.push('VERSION:2.0');
  lines.push('PRODID:-//SolenStay//Cleaning Schedule//KO');
  lines.push(`X-WR-CALNAME:${icsEscape(`SolenStay 청소 (${userName})`)}`);
  lines.push('X-WR-TIMEZONE:Asia/Seoul');
  lines.push('METHOD:PUBLISH');

  const stamp = utcStamp(new Date());

  for (const { d, c, r } of items) {
    if (!c.scheduledDate) continue;
    const date = c.scheduledDate.toDate();
    const nextDay = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1);
    const branchName = branchNames[c.branchId ?? ''] ?? (c.branchId ?? '');
    const guest = r?.guestName ?? '';
    const count = r?.guestCount ?? 0;
    const summary = guest
      ? `[${branchName}] 청소 — ${guest}${count > 0 ? `(${count}명)` : ''}`
      : `[${branchName}] 청소`;
    const desc = guest
      ? `호점: ${branchName}\\n게스트: ${guest}${count > 0 ? ` (${count}명)` : ''}`
      : `호점: ${branchName}`;

    lines.push('BEGIN:VEVENT');
    lines.push(`UID:cleaning_${d.id}@solenstay`);
    lines.push(`DTSTAMP:${stamp}`);
    lines.push(`DTSTART;VALUE=DATE:${ymd(date)}`);
    lines.push(`DTEND;VALUE=DATE:${ymd(nextDay)}`);
    lines.push(`SUMMARY:${icsEscape(summary)}`);
    lines.push(`DESCRIPTION:${icsEscape(desc)}`);
    lines.push('STATUS:CONFIRMED');
    lines.push('TRANSP:TRANSPARENT');
    lines.push('END:VEVENT');
  }

  lines.push('END:VCALENDAR');

  // CRLF로 합쳐서 응답 (RFC 5545)
  const body = lines.join('\r\n') + '\r\n';
  res.set('Content-Type', 'text/calendar; charset=utf-8');
  res.set('Cache-Control', 'public, max-age=900'); // 15분 캐시
  res.status(200).send(body);
});
