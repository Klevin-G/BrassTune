import { describe, expect, it } from 'vitest';
import { MAX_SCORE_PAGES, MAX_SCORE_PIXELS, pdfPageLimitMessage, scoreAcceptAttribute, scoreSourceKind, sniffScoreKind, verifiedScoreSourceKind, verifyScoreFile } from './scorePractice';

function testFile(name: string, type: string, size = 120_000) {
  return new File([new Uint8Array(size)], name, { type });
}

describe('score practice imports', () => {
  it('accepts PDFs and common image formats', () => {
    expect(scoreSourceKind(testFile('solo.pdf', 'application/pdf'))).toBe('pdf');
    expect(scoreSourceKind(testFile('part.heic', ''))).toBe('image');
    expect(scoreSourceKind(testFile('scan.webp', 'image/webp'))).toBe('image');
    expect(scoreAcceptAttribute()).toContain('image/png');
  });

  it('rejects unsupported active or unknown formats', () => {
    const summary = verifyScoreFile(testFile('unsafe.svg', 'image/svg+xml'));
    expect(summary.supported).toBe(false);
    expect(summary.kind).toBe('unsupported');
  });

  it('rejects active content even when the extension is spoofed', async () => {
    const file = new File(['<svg><script>alert(1)</script></svg>'], 'score.png', { type: '' });
    await expect(verifiedScoreSourceKind(file)).resolves.toBe('unsupported');
  });

  it('rejects corrupt files even when MIME types and extensions claim support', async () => {
    const corruptPdf = new File(['definitely not a PDF'], 'broken.pdf', { type: 'application/pdf' });
    const corruptJpeg = new File(['definitely not a JPEG'], 'broken.jpg', { type: 'image/jpeg' });

    await expect(verifiedScoreSourceKind(corruptPdf)).resolves.toBe('unsupported');
    await expect(verifiedScoreSourceKind(corruptJpeg)).resolves.toBe('unsupported');
  });

  it('accepts image ISO-BMFF brands but rejects unrelated ftyp containers', () => {
    const header = (majorBrand: string, minorVersion = new Uint8Array(4), compatibleBrand?: string) => {
      const byteLength = compatibleBrand ? 20 : 16;
      const bytes = new Uint8Array(byteLength);
      bytes.set([0, 0, 0, byteLength, 0x66, 0x74, 0x79, 0x70]);
      bytes.set(new TextEncoder().encode(majorBrand), 8);
      bytes.set(minorVersion, 12);
      if (compatibleBrand) bytes.set(new TextEncoder().encode(compatibleBrand), 16);
      return bytes;
    };

    expect(sniffScoreKind(header('heic'))).toBe('image');
    expect(sniffScoreKind(header('avif'))).toBe('image');
    expect(sniffScoreKind(header('isom'))).toBe('unsupported');
    expect(sniffScoreKind(header('mp42', new TextEncoder().encode('heic')))).toBe('unsupported');
    expect(sniffScoreKind(header('isom', new Uint8Array(4), 'avif'))).toBe('image');
  });

  it('requires complete PDF and PNG magic signatures', () => {
    expect(sniffScoreKind(new TextEncoder().encode('%PDF-1.7\n'))).toBe('pdf');
    expect(sniffScoreKind(new TextEncoder().encode('  %PDF-1.7\n'))).toBe('unsupported');
    expect(sniffScoreKind(new Uint8Array([0x89, 0x50, 0x4e, 0x47]))).toBe('unsupported');
    expect(sniffScoreKind(new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))).toBe('image');
  });

  it('flags low resolution and likely non-music images without discarding them', () => {
    const summary = verifyScoreFile(testFile('receipt-photo.jpg', 'image/jpeg'), { width: 700, height: 500 });
    expect(summary.supported).toBe(true);
    expect(summary.quality.status).toBe('review');
    expect(summary.quality.messages.join(' ')).toMatch(/higher-resolution|Possible non-music/);
  });

  it('blocks decoded images above the pixel budget', () => {
    const side = Math.ceil(Math.sqrt(MAX_SCORE_PIXELS)) + 1;
    const summary = verifyScoreFile(testFile('huge-score.png', 'image/png'), { width: side, height: side });
    expect(summary.supported).toBe(false);
    expect(summary.quality.messages.join(' ')).toMatch(/decoded dimensions/);
  });

  it('reports PDFs that exceed the local page budget', () => {
    expect(pdfPageLimitMessage(MAX_SCORE_PAGES)).toBeNull();
    expect(pdfPageLimitMessage(MAX_SCORE_PAGES + 1)).toMatch(/Split it into 64 pages or fewer/);
  });
});
