import { Buffer } from 'node:buffer';
import { expect, test, type Page } from 'playwright/test';

const DB_NAME = 'brasstune-score-practice';
const STORE_NAME = 'scoreDocuments';

function makeBlankPdf(pageCount: number) {
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    `<< /Type /Pages /Kids [${Array.from({ length: pageCount }, (_, index) => `${index + 3} 0 R`).join(' ')}] /Count ${pageCount} >>`,
    ...Array.from({ length: pageCount }, () => '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 144 144] /Resources << >> >>'),
  ];
  let contents = '%PDF-1.4\n';
  const offsets = [0];
  objects.forEach((object, index) => {
    offsets.push(Buffer.byteLength(contents, 'ascii'));
    contents += `${index + 1} 0 obj\n${object}\nendobj\n`;
  });
  const xrefOffset = Buffer.byteLength(contents, 'ascii');
  contents += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  contents += offsets.slice(1).map((offset) => `${offset.toString().padStart(10, '0')} 00000 n \n`).join('');
  contents += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF\n`;
  return Buffer.from(contents, 'ascii');
}

async function savedDocumentCount(page: Page) {
  return page.evaluate(({ dbName, storeName }) => new Promise<number>((resolve, reject) => {
    const open = indexedDB.open(dbName, 1);
    open.onupgradeneeded = () => open.result.createObjectStore(storeName, { keyPath: 'id' });
    open.onerror = () => reject(open.error);
    open.onsuccess = () => {
      const db = open.result;
      const transaction = db.transaction(storeName, 'readonly');
      const count = transaction.objectStore(storeName).count();
      let result = 0;
      count.onsuccess = () => { result = count.result; };
      count.onerror = () => reject(new Error(`Count failed: ${count.error?.name ?? 'unknown error'}`));
      transaction.oncomplete = () => {
        db.close();
        resolve(result);
      };
      transaction.onerror = () => {
        db.close();
        reject(new Error(`Count transaction failed: ${transaction.error?.name ?? 'unknown error'}`));
      };
      transaction.onabort = () => reject(new Error(`Count transaction aborted: ${transaction.error?.name ?? 'unknown error'}`));
    };
  }), { dbName: DB_NAME, storeName: STORE_NAME });
}

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    localStorage.setItem('brasstune.onboardingComplete', 'true');
    localStorage.setItem('brasstune.guestOnboardingComplete', 'true');
    localStorage.setItem('brasstune.demoMode', 'true');
    localStorage.setItem('brasstune.guestAccess', 'true');
  });
});

test('a corrupt image with JPEG magic fails closed before persistence', async ({ page }) => {
  await page.goto('/practice/score');
  const fileInput = page.getByLabel('Choose Files', { exact: true });
  await fileInput.setInputFiles({
    name: 'broken.jpg',
    mimeType: 'image/jpeg',
    buffer: Buffer.from([0xff, 0xd8, 0xff, 0x00, 0x01, 0x02]),
  });
  const status = page.locator('.sm-status');
  await expect(status).toContainText('broken.jpg');
  await expect(status).toContainText('could not be decoded as a valid image.');
  expect(await savedDocumentCount(page)).toBe(0);
});

test('a 65-page PDF is rejected before persistence', async ({ page, browserName }) => {
  test.skip(browserName === 'firefox', 'Playwright Firefox does not deliver the synthetic PDF File through file input or DataTransfer.');
  await page.goto('/practice/score');
  const oversizedPdf = makeBlankPdf(65);
  const dataTransfer = await page.evaluateHandle((base64) => {
    const binary = atob(base64);
    const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
    const transfer = new DataTransfer();
    transfer.items.add(new File([bytes], 'oversized.pdf', { type: 'application/pdf' }));
    return transfer;
  }, oversizedPdf.toString('base64'));
  await page.locator('.sm-import-dropzone').dispatchEvent('drop', { dataTransfer });
  await expect(page.getByText(/split it into 64 pages or fewer/i)).toBeVisible();
  expect(await savedDocumentCount(page)).toBe(0);
});

test('a concurrent import is preserved while saved music hydrates', async ({ page, browserName }) => {
  test.skip(browserName !== 'chromium', 'This test deliberately controls Chromium IndexedDB and File read scheduling.');
  await page.goto('/privacy');
  const savedPdf = makeBlankPdf(1);
  await page.evaluate(async ({ base64, dbName, storeName }) => {
    const db = await new Promise<IDBDatabase>((resolve, reject) => {
      const open = indexedDB.open(dbName, 1);
      open.onupgradeneeded = () => open.result.createObjectStore(storeName, { keyPath: 'id' });
      open.onerror = () => reject(open.error);
      open.onsuccess = () => resolve(open.result);
    });
    await new Promise<void>((resolve, reject) => {
      const transaction = db.transaction(storeName, 'readwrite');
      const binary = atob(base64);
      const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
      transaction.objectStore(storeName).put({
        id: 'slow-saved',
        name: 'slow-saved.pdf',
        source: 'files',
        kind: 'pdf',
        type: 'application/pdf',
        blob: new File([bytes], 'slow-saved.pdf', { type: 'application/pdf' }),
      });
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(transaction.error);
      transaction.onabort = () => reject(transaction.error);
    });
    db.close();
  }, { base64: savedPdf.toString('base64'), dbName: DB_NAME, storeName: STORE_NAME });
  await page.addInitScript(() => {
    const originalArrayBuffer = File.prototype.arrayBuffer;
    File.prototype.arrayBuffer = function delayedSavedPdfRead() {
      if (this.name !== 'slow-saved.pdf') return originalArrayBuffer.call(this);
      return new Promise<ArrayBuffer>((resolve, reject) => {
        setTimeout(() => originalArrayBuffer.call(this).then(resolve, reject), 500);
      });
    };
  });

  await page.goto('/practice/score');
  await page.getByLabel('Choose Files', { exact: true }).setInputFiles({
    name: 'new-import.pdf',
    mimeType: 'application/pdf',
    buffer: makeBlankPdf(1),
  });

  await expect(page.getByRole('button', { name: /Page 1.*new-import\.pdf/i })).toBeVisible();
  await expect(page.getByRole('button', { name: /Page 2.*slow-saved\.pdf/i })).toBeVisible();
  expect(await savedDocumentCount(page)).toBe(2);
});

test('oversized legacy PDFs are purged and delete failures are reported honestly', async ({ page, browserName }) => {
  test.skip(browserName !== 'chromium', 'This test deliberately injects Chromium IndexedDB rows and transaction failures.');
  await page.goto('/privacy');
  const fileInput = page.getByLabel('Choose Files', { exact: true });
  const oversizedPdf = makeBlankPdf(65);
  await page.evaluate(async ({ base64, dbName, storeName }) => {
    const db = await new Promise<IDBDatabase>((resolve, reject) => {
      const open = indexedDB.open(dbName, 1);
      open.onupgradeneeded = () => open.result.createObjectStore(storeName, { keyPath: 'id' });
      open.onerror = () => reject(open.error);
      open.onsuccess = () => resolve(open.result);
    });
    await new Promise<void>((resolve, reject) => {
      const transaction = db.transaction(storeName, 'readwrite');
      const binary = atob(base64);
      const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
      const store = transaction.objectStore(storeName);
      const put = store.put({
        id: 'legacy-oversized',
        name: 'legacy-oversized.pdf',
        source: 'files',
        kind: 'pdf',
        type: 'application/pdf',
        blob: new File([bytes], 'legacy-oversized.pdf', { type: 'application/pdf' }),
      });
      put.onerror = () => reject(new Error(`Legacy row put failed: ${put.error?.name ?? 'unknown error'}`));
      store.put({
        id: 'legacy-malformed',
        name: 7,
        source: 'files',
        kind: 'pdf',
        type: 'application/pdf',
        blob: new File([bytes], 'legacy-malformed.pdf', { type: 'application/pdf' }),
      });
      transaction.oncomplete = () => resolve();
      transaction.onerror = () => reject(new Error(`Legacy row transaction failed: ${transaction.error?.name ?? 'unknown error'}`));
      transaction.onabort = () => reject(new Error(`Legacy row transaction aborted: ${transaction.error?.name ?? 'unknown error'}`));
    });
    db.close();
  }, { base64: oversizedPdf.toString('base64'), dbName: DB_NAME, storeName: STORE_NAME });

  await page.goto('/practice/score');
  await expect(page.getByText(/removed 2 saved files that could not be opened safely/i)).toBeVisible();
  await expect(page.getByText('legacy-oversized.pdf')).toHaveCount(0);
  await expect.poll(() => savedDocumentCount(page)).toBe(0);

  await fileInput.setInputFiles({ name: 'one-page.pdf', mimeType: 'application/pdf', buffer: makeBlankPdf(1) });
  await expect(page.getByText('Added your page.')).toBeVisible();
  await expect(page.getByLabel(/Sheet music page for.*one-page\.pdf/i)).toBeVisible();
  await expect.poll(() => savedDocumentCount(page)).toBe(1);

  await page.evaluate(() => {
    const originalDelete = IDBObjectStore.prototype.delete;
    IDBObjectStore.prototype.delete = function forcedAbort(key: IDBValidKey) {
      const request = originalDelete.call(this, key);
      this.transaction.abort();
      return request;
    };
  });
  await page.getByRole('button', { name: 'More options' }).click();
  await page.getByRole('menuitem', { name: /delete this page/i }).click();
  await page.getByRole('button', { name: 'Remove', exact: true }).click();

  await expect(page.getByText(/could(?: not|n['’]t) be removed.*still in your saved music/i)).toBeVisible();
  await expect(page.getByLabel(/Sheet music page for.*one-page\.pdf/i)).toBeVisible();
  await expect.poll(() => savedDocumentCount(page)).toBe(1);
});
