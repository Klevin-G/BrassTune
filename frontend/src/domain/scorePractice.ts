export type ScoreSourceKind = 'pdf' | 'image' | 'unsupported';

export interface ScorePageQuality {
  status: 'good' | 'review' | 'unsupported';
  messages: string[];
  likelySheetMusicScore: number;
}

export interface ScoreImportSummary {
  kind: ScoreSourceKind;
  supported: boolean;
  label: string;
  quality: ScorePageQuality;
}

export const MAX_SCORE_FILE_BYTES = 80 * 1024 * 1024;
export const MAX_SCORE_PIXELS = 32_000_000;
export const MAX_SCORE_PAGES = 64;
export const MIN_SCORE_WIDTH = 900;
export const MIN_SCORE_HEIGHT = 900;

const ACTIVE_MIME_TYPES = new Set(['image/svg+xml', 'text/html', 'application/xhtml+xml']);
const IMAGE_EXTENSIONS = new Set(['jpg', 'jpeg', 'png', 'heic', 'heif', 'webp', 'tif', 'tiff', 'bmp', 'avif', 'gif']);
const IMAGE_MIME_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/heic',
  'image/heif',
  'image/webp',
  'image/tiff',
  'image/bmp',
  'image/avif',
  'image/gif',
]);

const PDF_MIME_TYPES = new Set(['application/pdf']);

export function sniffScoreKind(header: Uint8Array): ScoreSourceKind {
  const ascii = new TextDecoder('latin1').decode(header.slice(0, 64)).trimStart().toLowerCase();
  if (ascii.startsWith('%pdf-')) return 'pdf';
  if (header[0] === 0xff && header[1] === 0xd8 && header[2] === 0xff) return 'image';
  if (header[0] === 0x89 && header[1] === 0x50 && header[2] === 0x4e && header[3] === 0x47) return 'image';
  if (ascii.startsWith('gif87a') || ascii.startsWith('gif89a')) return 'image';
  if (header[0] === 0x52 && header[1] === 0x49 && header[2] === 0x46 && header[3] === 0x46 && header[8] === 0x57 && header[9] === 0x45 && header[10] === 0x42 && header[11] === 0x50) return 'image';
  if ((header[0] === 0x49 && header[1] === 0x49 && header[2] === 0x2a && header[3] === 0x00) || (header[0] === 0x4d && header[1] === 0x4d && header[2] === 0x00 && header[3] === 0x2a)) return 'image';
  if (header[0] === 0x42 && header[1] === 0x4d) return 'image';
  if (header[4] === 0x66 && header[5] === 0x74 && header[6] === 0x79 && header[7] === 0x70) return 'image';
  if (ascii.startsWith('<svg') || ascii.includes('<script') || ascii.startsWith('<!doctype html') || ascii.startsWith('<html')) return 'unsupported';
  return 'unsupported';
}

function hasActiveHeader(header: Uint8Array) {
  const ascii = new TextDecoder('latin1').decode(header.slice(0, 256)).trimStart().toLowerCase();
  return ascii.startsWith('<svg') || ascii.includes('<script') || ascii.startsWith('<!doctype html') || ascii.startsWith('<html');
}

export function fileExtension(name: string) {
  const match = /\.([a-z0-9]+)$/i.exec(name);
  return match ? match[1].toLowerCase() : '';
}

export function scoreSourceKind(file: Pick<File, 'name' | 'type'>): ScoreSourceKind {
  if (ACTIVE_MIME_TYPES.has(file.type)) return 'unsupported';
  const extension = fileExtension(file.name);
  if (PDF_MIME_TYPES.has(file.type) || extension === 'pdf') return 'pdf';
  if (IMAGE_MIME_TYPES.has(file.type) || IMAGE_EXTENSIONS.has(extension)) return 'image';
  return 'unsupported';
}

export async function verifiedScoreSourceKind(file: File): Promise<ScoreSourceKind> {
  if (ACTIVE_MIME_TYPES.has(file.type)) return 'unsupported';
  const header = new Uint8Array(await file.slice(0, 64).arrayBuffer());
  if (hasActiveHeader(header)) return 'unsupported';
  const sniffed = sniffScoreKind(header);
  if (sniffed !== 'unsupported') return sniffed;
  return scoreSourceKind(file);
}

export function likelySheetMusicFromName(name: string) {
  const normalized = name.toLowerCase();
  let score = 0.35;
  if (/(score|sheet|music|etude|study|solo|part|movement|rehearsal|measure|staff|chorale)/.test(normalized)) score += 0.28;
  if (/\b(pdf|part|score)\b/.test(normalized)) score += 0.12;
  if (/(photo|portrait|selfie|receipt|invoice|screenshot)/.test(normalized)) score -= 0.22;
  return Math.max(0, Math.min(1, score));
}

// Presentation only: turns the filename/format heuristic into an honest hint.
// This is a quick check of the file name and size, not content analysis or note recognition.
export function sheetMusicNameHint(score: number): string {
  if (score >= 0.55) return 'Filename looks like a score';
  if (score >= 0.42) return 'Filename check: possible score';
  return 'Filename check inconclusive';
}

export function verifyScoreFile(file: File, dimensions?: { width: number; height: number }, verifiedKind?: ScoreSourceKind): ScoreImportSummary {
  const kind = verifiedKind ?? scoreSourceKind(file);
  const messages: string[] = [];
  if (kind === 'unsupported') {
    return {
      kind,
      supported: false,
      label: 'Unsupported format',
      quality: { status: 'unsupported', messages: ['Choose a PDF or common image format.'], likelySheetMusicScore: 0 },
    };
  }
  if (file.size <= 0) messages.push('File is empty.');
  if (file.size > MAX_SCORE_FILE_BYTES) messages.push('File is too large for local score practice.');
  let likelySheetMusicScore = likelySheetMusicFromName(file.name);
  if (kind === 'pdf') {
    messages.push('PDF preview is ready. Page count and note recognition are not inferred.');
  }
  if (kind === 'image' && dimensions) {
    const pixels = dimensions.width * dimensions.height;
    if (dimensions.width < MIN_SCORE_WIDTH || dimensions.height < MIN_SCORE_HEIGHT) messages.push('Move closer or use a higher-resolution image.');
    if (pixels > MAX_SCORE_PIXELS) messages.push('Image decoded dimensions are too large for safe local practice.');
    if (dimensions.width > dimensions.height * 1.7 || dimensions.height > dimensions.width * 2.4) messages.push('Review crop and rotation before practice.');
    if (dimensions.width >= 1400 && dimensions.height >= 1400) likelySheetMusicScore += 0.1;
  }
  if (kind === 'image' && file.type === 'image/gif') {
    messages.push('Animated GIFs use only the first frame for practice.');
  }
  if (likelySheetMusicScore < 0.42) messages.push('Possible non-music image. Review before practice.');
  const blocking = messages.some((message) => /empty|too large|unsupported|decoded dimensions/i.test(message));
  return {
    kind,
    supported: !blocking,
    label: blocking ? 'Review file' : messages.length ? 'Review before practice' : 'Good scan',
    quality: {
      status: blocking ? 'unsupported' : messages.length ? 'review' : 'good',
      messages: messages.length ? messages : ['Good scan'],
      likelySheetMusicScore: Math.max(0, Math.min(1, likelySheetMusicScore)),
    },
  };
}

export function pdfPageLimitMessage(pageCount: number) {
  return pageCount > MAX_SCORE_PAGES
    ? `PDF has ${pageCount} pages. Split it into ${MAX_SCORE_PAGES} pages or fewer before import.`
    : null;
}

export function scoreAcceptAttribute() {
  return 'application/pdf,image/jpeg,image/png,image/heic,image/heif,image/webp,image/tiff,image/bmp,image/avif,image/gif';
}
