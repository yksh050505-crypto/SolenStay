/**
 * SolenStay Cloud Functions 공통 상수
 */

export const REGION = 'asia-northeast3';
export const TIMEZONE = 'Asia/Seoul';

/** iCal 동기화 주기 (분) */
export const ICAL_SYNC_INTERVAL_MIN = 1;

/** 미지정 청소 알림 검사 주기 (분) */
export const UNASSIGNED_CHECK_INTERVAL_MIN = 60;

/** 체크아웃 N시간 전 알림 */
export const REMINDER_HOURS_BEFORE_CHECKOUT = 4;

/** 사진 보존 일수 */
export const PHOTO_RETENTION_DAYS = 30;

/** 사진 자동 삭제 검사 주기 (cron 표현식 — 매일 03:00 KST) */
export const PHOTO_CLEANUP_CRON = '0 3 * * *';

/** PIN 정규식: 4~8자리 숫자 */
export const PIN_REGEX = /^\d{4,8}$/;

/** 사진 최대 크기 (5MB) */
export const MAX_PHOTO_SIZE_BYTES = 5 * 1024 * 1024;
