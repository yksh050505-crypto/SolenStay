/**
 * 유지보수 함수
 *
 * - cleanupOldPhotos: Scheduled (매일 03:00 KST), 30일 이상 된 청소 사진 Storage 삭제 + photoUrls 정리
 */

import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as admin from 'firebase-admin';
import { REGION, TIMEZONE, PHOTO_CLEANUP_CRON, PHOTO_RETENTION_DAYS } from './lib/constants';

/**
 * Scheduled: 30일 이상 된 완료 청소의 사진 정리
 */
export const cleanupOldPhotos = onSchedule(
  {
    region: REGION,
    schedule: PHOTO_CLEANUP_CRON,
    timeZone: TIMEZONE,
    timeoutSeconds: 540,
    memory: '512MiB',
  },
  async () => {
    const db = admin.firestore();
    const storage = admin.storage().bucket();

    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - PHOTO_RETENTION_DAYS * 24 * 60 * 60 * 1000,
    );

    const snap = await db
      .collection('cleanings')
      .where('completedAt', '<=', cutoff)
      .get();

    let deletedFiles = 0;
    let updatedDocs = 0;

    for (const doc of snap.docs) {
      const photoUrls = (doc.data().photoUrls as string[]) ?? [];
      if (photoUrls.length === 0) continue;

      // Storage 경로는 'cleanings/{cleaningId}/...' 형태로 저장
      const prefix = `cleanings/${doc.id}/`;
      const [files] = await storage.getFiles({ prefix });

      for (const file of files) {
        try {
          await file.delete();
          deletedFiles++;
        } catch (err) {
          console.error(`[cleanup] failed to delete ${file.name}:`, err);
        }
      }

      await doc.ref.update({ photoUrls: [] });
      updatedDocs++;
    }

    console.log(
      `[cleanupOldPhotos] cutoff=${cutoff.toDate().toISOString()}, ` +
        `processed=${snap.size}, files=${deletedFiles}, docs=${updatedDocs}`,
    );
  },
);
