/**
 * 공통 헬퍼 함수
 */

import * as crypto from 'crypto';
import { HttpsError, CallableRequest } from 'firebase-functions/v2/https';

/** PIN HMAC-SHA256 해시 */
export function hashPin(pin: string, salt: string): string {
  return crypto.createHmac('sha256', salt).update(pin).digest('hex');
}

/** 16바이트 랜덤 salt 생성 (hex) */
export function generateSalt(): string {
  return crypto.randomBytes(16).toString('hex');
}

/** 인증 확인. 미인증 시 throw */
export function requireAuth(req: CallableRequest): NonNullable<CallableRequest['auth']> {
  if (!req.auth) {
    throw new HttpsError('unauthenticated', 'login required');
  }
  return req.auth;
}

/** role이 manager인지 확인 */
export function requireManager(req: CallableRequest): NonNullable<CallableRequest['auth']> {
  const auth = requireAuth(req);
  if (auth.token?.role !== 'manager') {
    throw new HttpsError('permission-denied', 'manager only');
  }
  return auth;
}

/** role이 chief 또는 manager인지 확인 */
export function requireChiefOrManager(req: CallableRequest): NonNullable<CallableRequest['auth']> {
  const auth = requireAuth(req);
  const role = auth.token?.role;
  if (role !== 'manager' && role !== 'chief') {
    throw new HttpsError('permission-denied', 'chief or manager only');
  }
  return auth;
}
