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
 * 청소원/실장/매니저가 이름+PIN으로 로그인
 * @returns { token: string, role: string, name: string, pinChanged: boolean }
 */
export const signInWithPin = onCall({ region: REGION }, async (req) => {
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

  if (typeof newPin !== 'string' || !PIN_REGEX.test(newPin)) {
    throw new HttpsError('invalid-argument', 'newPin must be 4-8 digits');
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
