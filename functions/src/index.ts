/**
 * SolenStay Cloud Functions 엔트리
 * Region: asia-northeast3 (Seoul)
 *
 * Phase 3 진행 상황:
 *   ✅ 인증: signInWithPin, changePin, registerUser, updateUserPin, deactivateUser
 *   ✅ iCal 동기화: syncICalScheduled, syncICalManual
 *   ✅ 청소: onReservationCreated, claimCleaning, releaseCleaning, forceAssignCleaning, completeCleaning
 *   ✅ 알림: notifyUnassignedReminder, notifyNewReservation, registerFcmToken, unregisterFcmToken
 *   ✅ 유지보수: cleanupOldPhotos
 *
 * 총 14개 함수 모두 구현 완료.
 */

import * as admin from 'firebase-admin';

admin.initializeApp();

// ===== 인증 =====
export {
  listLoginCandidates,
  signInWithPin,
  changePin,
  registerUser,
  updateUserPin,
  deactivateUser,
} from './auth_pin';

// ===== iCal 동기화 =====
export { syncICalScheduled, syncICalManual } from './ical_sync';

// ===== 청소 =====
export {
  onReservationCreated,
  claimCleaning,
  releaseCleaning,
  forceAssignCleaning,
  completeCleaning,
} from './cleanings';

// ===== 알림 =====
export {
  notifyUnassignedReminder,
  notifyNewReservation,
  registerFcmToken,
  unregisterFcmToken,
} from './notifications';

// ===== 유지보수 =====
export { cleanupOldPhotos } from './maintenance';
