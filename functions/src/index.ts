/**
 * SolenStay Cloud Functions 엔트리
 * Region: asia-northeast3 (Seoul)
 *
 * Phase 3 진행 상황:
 *   ✅ 인증: signInWithPin, changePin, registerUser, updateUserPin, deactivateUser
 *   ⏳ iCal 동기화: syncICalScheduled, syncICalManual (다음 단계)
 *   ⏳ 청소: claimCleaning, releaseCleaning, completeCleaning, forceAssignCleaning, onReservationCreated
 *   ⏳ 알림: notifyUnassignedReminder, notifyNewReservation, registerFcmToken, unregisterFcmToken
 *   ⏳ 유지보수: cleanupOldPhotos
 */

import * as admin from 'firebase-admin';

admin.initializeApp();

// ===== 인증 =====
export {
  signInWithPin,
  changePin,
  registerUser,
  updateUserPin,
  deactivateUser,
} from './auth_pin';
