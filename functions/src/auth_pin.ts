/**
 * PIN 기반 인증 함수
 *
 * - signInWithPin: 이름+PIN으로 Custom Token 발급
 * - changePin: 본인 PIN 변경 (초기 000000 → 새 PIN)
 * - registerUser: 매니저가 신규 사용자 등록
 * - updateUserPin: 매니저가 사용자 PIN 강제 변경
 * - deactivateUser: 매니저가 사용자 비활성화
 */

import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import { REGION, PIN_REGEX } from './lib/constants';
import { hashPin, generateSalt, requireAuth, requireManager } from './lib/helpers';

interface UserDoc {
  name: string;
  role: 'manager' | 'chief' | 'cleaner';
  pinHash: string;
  pinSalt: string;
  pinChanged: boolean;
  fcmTokens: string[];
  active: boolean;
  createdAt?: admin.firestore.Timestamp;
}

/**
 * 로그인 화면용: 활성 사용자 이름 목록 반환 (PIN 정보 없이)
 * 인증 없이 호출 가능 (이름 카드 표시용)
 * @param data { adminOnly?: boolean } — true면 매니저/실장만, false(기본)면 청소원만
 */
export const listLoginCandidates = onCall({ region: REGION, minInstances: 1 }, async (req) => {
  const adminOnly = (req.data?.adminOnly as boolean | undefined) === true;
  const db = admin.firestore();
  const snap = await db.collection('users').where('active', '==', true).get();

  const filtered = snap.docs.filter((d) => {
    const role = (d.data().role as string | undefined) ?? 'cleaner';
    // 관리자 모드: manager + chief
    // 청소원 모드: cleaner + chief (실장은 양쪽 모두 표시 — 직접 청소도 함)
    return adminOnly
      ? (role === 'manager')
      : (role === 'cleaner' || role === 'chief');
  });

  const names = Array.from(new Set(filtered.map((d) => d.data().name as string)))
    .filter((n): n is string => typeof n === 'string' && n.length > 0)
    .sort();
  return { names };
});

/**
 * 청소원/실장/매니저가 이름+PIN으로 로그인
 * @returns { token: string, role: string, name: string, pinChanged: boolean }
 */
export const signInWithPin = onCall({ region: REGION, minInstances: 1 }, async (req) => {
  const { name, pin } = req.data ?? {};

  if (typeof name !== 'string' || !name.trim()) {
    throw new HttpsError('invalid-argument', 'name required');
  }
  if (typeof pin !== 'string' || !PIN_REGEX.test(pin)) {
    throw new HttpsError('invalid-argument', 'pin must be 4-8 digits');
  }

  const db = admin.firestore();
  const snap = await db
    .collection('users')
    .where('name', '==', name.trim())
    .where('active', '==', true)
    .get();

  for (const doc of snap.docs) {
    const u = doc.data() as UserDoc;
    if (hashPin(pin, u.pinSalt) === u.pinHash) {
      const token = await admin.auth().createCustomToken(doc.id, { role: u.role });
      return {
        token,
        role: u.role,
        name: u.name,
        pinChanged: u.pinChanged,
      };
    }
  }

  // 보안: 어떤 필드가 틀렸는지 노출하지 않음
  throw new HttpsError('unauthenticated', 'invalid name or pin');
});

/**
 * 본인 PIN 변경 (초기 000000 → 새 PIN 또는 PIN 분실 시 매니저 강제 변경 후 본인 재변경)
 * @param data { newPin: string }
 */
export const changePin = onCall({ region: REGION }, async (req) => {
  const auth = requireAuth(req);
  const { newPin } = req.data ?? {};

  if (typeof newPin !== 'string' || !/^\d{6}$/.test(newPin)) {
    throw new HttpsError('invalid-argument', 'newPin must be exactly 6 digits');
  }

  // 너무 단순한 PIN 거부 (000000 같은 초기값은 변경 후 재사용 불가)
  if (newPin === '000000' || /^(\d)\1+$/.test(newPin)) {
    throw new HttpsError('invalid-argument', '단순한 PIN은 사용할 수 없습니다');
  }

  const salt = generateSalt();
  await admin.firestore().collection('users').doc(auth.uid).update({
    pinHash: hashPin(newPin, salt),
    pinSalt: salt,
    pinChanged: true,
  });

  return { ok: true };
});

/**
 * 매니저가 신규 사용자 등록
 * @param data { name: string, pin: string, role: 'chief' | 'cleaner' | 'manager' }
 */
export const registerUser = onCall({ region: REGION }, async (req) => {
  requireManager(req);

  const { name, pin, role } = req.data ?? {};

  if (typeof name !== 'string' || !name.trim()) {
    throw new HttpsError('invalid-argument', 'name required');
  }
  if (typeof pin !== 'string' || !PIN_REGEX.test(pin)) {
    throw new HttpsError('invalid-argument', 'pin must be 4-8 digits');
  }
  if (role !== 'manager' && role !== 'chief' && role !== 'cleaner') {
    throw new HttpsError('invalid-argument', 'role must be manager/chief/cleaner');
  }

  // 중복 이름 검사 (active 사용자만)
  const dup = await admin
    .firestore()
    .collection('users')
    .where('name', '==', name.trim())
    .where('active', '==', true)
    .limit(1)
    .get();
  if (!dup.empty) {
    throw new HttpsError('already-exists', '같은 이름의 활성 사용자가 이미 있습니다');
  }

  const salt = generateSalt();
  const userRecord = await admin.auth().createUser({ displayName: name.trim() });
  await admin.auth().setCustomUserClaims(userRecord.uid, { role });

  await admin.firestore().collection('users').doc(userRecord.uid).set({
    name: name.trim(),
    role,
    pinHash: hashPin(pin, salt),
    pinSalt: salt,
    pinChanged: false,
    fcmTokens: [],
    active: true,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { uid: userRecord.uid };
});

/**
 * 매니저가 사용자 PIN 강제 변경 (PIN 분실 시)
 * @param data { uid: string, pin: string }
 */
export const updateUserPin = onCall({ region: REGION }, async (req) => {
  requireManager(req);

  const { uid, pin } = req.data ?? {};

  if (typeof uid !== 'string' || !uid) {
    throw new HttpsError('invalid-argument', 'uid required');
  }
  if (typeof pin !== 'string' || !PIN_REGEX.test(pin)) {
    throw new HttpsError('invalid-argument', 'pin must be 4-8 digits');
  }

  const salt = generateSalt();
  await admin.firestore().collection('users').doc(uid).update({
    pinHash: hashPin(pin, salt),
    pinSalt: salt,
    pinChanged: false, // 다음 로그인 시 다시 변경하도록
  });

  return { ok: true };
});

/**
 * 매니저가 사용자 비활성화 (퇴사 처리)
 * @param data { uid: string }
 */
export const deactivateUser = onCall({ region: REGION }, async (req) => {
  requireManager(req);

  const { uid } = req.data ?? {};
  if (typeof uid !== 'string' || !uid) {
    throw new HttpsError('invalid-argument', 'uid required');
  }

  await admin.firestore().collection('users').doc(uid).update({ active: false });
  await admin.auth().updateUser(uid, { disabled: true });

  return { ok: true };
});

/**
 * 본인 프로필 자가 수정 (이름 / 프로필 사진 / 언어)
 * Firestore 규칙상 클라이언트는 name/photoUrl/language를 직접 못 바꾸므로 함수 경유.
 * @param data { name?: string, photoUrl?: string|null, language?: 'ko'|'en' }
 */
export const updateMyProfile = onCall({ region: REGION }, async (req) => {
  const auth = requireAuth(req);
  const { name, photoUrl, language, notificationPrefs } = req.data ?? {};

  const updates: Record<string, unknown> = {};

  if (name !== undefined) {
    if (typeof name !== 'string' || !name.trim()) {
      throw new HttpsError('invalid-argument', 'name invalid');
    }
    const trimmed = name.trim();
    // 활성 사용자 중 본인 제외 이름 중복 검사 (로그인 식별자라 유일해야 함)
    const dup = await admin
      .firestore()
      .collection('users')
      .where('name', '==', trimmed)
      .where('active', '==', true)
      .limit(2)
      .get();
    if (dup.docs.some((d) => d.id !== auth.uid)) {
      throw new HttpsError('already-exists', '같은 이름의 사용자가 이미 있습니다');
    }
    updates.name = trimmed;
    await admin.auth().updateUser(auth.uid, { displayName: trimmed });
  }

  if (photoUrl !== undefined) {
    if (photoUrl !== null && typeof photoUrl !== 'string') {
      throw new HttpsError('invalid-argument', 'photoUrl invalid');
    }
    updates.photoUrl = photoUrl === null ? admin.firestore.FieldValue.delete() : photoUrl;
  }

  if (language !== undefined) {
    if (language !== 'ko' && language !== 'en') {
      throw new HttpsError('invalid-argument', 'language must be ko or en');
    }
    updates.language = language;
  }

  if (notificationPrefs !== undefined) {
    if (typeof notificationPrefs !== 'object' || notificationPrefs === null || Array.isArray(notificationPrefs)) {
      throw new HttpsError('invalid-argument', 'notificationPrefs must be an object');
    }
    const allowedKeys = new Set(['newCleaning', 'managerNotice', 'scheduleChange']);
    const sanitized: Record<string, boolean> = {};
    for (const [k, v] of Object.entries(notificationPrefs as Record<string, unknown>)) {
      if (!allowedKeys.has(k)) continue;
      if (typeof v !== 'boolean') continue;
      sanitized[k] = v;
    }
    updates.notificationPrefs = sanitized;
  }

  if (Object.keys(updates).length === 0) {
    return { ok: true };
  }

  await admin.firestore().collection('users').doc(auth.uid).update(updates);
  return { ok: true };
});

/**
 * 매니저가 사용자 완전 삭제 (Auth 계정 + Firestore 문서 제거)
 * 비활성화(deactivateUser)와 달리 기록을 남기지 않음.
 * @param data { uid: string }
 */
export const deleteUser = onCall({ region: REGION }, async (req) => {
  const caller = requireManager(req);

  const { uid } = req.data ?? {};
  if (typeof uid !== 'string' || !uid) {
    throw new HttpsError('invalid-argument', 'uid required');
  }
  if (uid === caller.uid) {
    throw new HttpsError('failed-precondition', '본인 계정은 삭제할 수 없습니다');
  }

  // Auth 계정 삭제 (이미 없으면 무시)
  try {
    await admin.auth().deleteUser(uid);
  } catch (e) {
    if ((e as { code?: string })?.code !== 'auth/user-not-found') throw e;
  }

  await admin.firestore().collection('users').doc(uid).delete();

  return { ok: true };
});
