import { describe, expect, it } from 'vitest';
import { MAX_SCORE_PIXELS, scoreAcceptAttribute, scoreSourceKind, verifiedScoreSourceKind, verifyScoreFile } from './scorePractice';

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
});
