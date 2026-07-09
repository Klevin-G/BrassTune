export const SCORE_DOCUMENTS_DB_NAME = 'brasstune-score-practice';
export const SCORE_DOCUMENTS_STORE_NAME = 'scoreDocuments';

export function clearLocalScoreDocuments() {
  return new Promise<void>((resolve, reject) => {
    if (typeof indexedDB === 'undefined') {
      resolve();
      return;
    }
    const request = indexedDB.deleteDatabase(SCORE_DOCUMENTS_DB_NAME);
    request.onsuccess = () => resolve();
    request.onblocked = () => reject(new Error('Close other BrassTune score pages, then try again.'));
    request.onerror = () => reject(request.error ?? new Error('Could not clear local score pages.'));
  });
}
