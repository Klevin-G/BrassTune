// Plain-language translations of raw tuning data, so beginner-facing surfaces
// never show a bare "+12c" without meaning. Shared by the tuner, Play-Along,
// Sessions, and Progress so the color grammar and wording stay identical.
//
// Color grammar (used everywhere): green = in tune, amber = a little off,
// red = off / needs work. Direction: below 0 = flat (too low), above = sharp.

export type TuneTone = 'green' | 'amber' | 'red' | 'muted';

export interface CentsVerdict {
  /** Short label a beginner understands, e.g. "In tune", "A little sharp". */
  label: string;
  /** Signed detail like "12¢ sharp" for users who want the number. */
  detail: string;
  /** One concrete coaching cue, e.g. "ease down". */
  cue: string;
  tone: TuneTone;
  direction: 'flat' | 'sharp' | 'center';
}

/** Interpret a signed cents deviation for the live tuner / a single note. */
export function describeCents(cents: number | null | undefined): CentsVerdict {
  if (cents == null || Number.isNaN(cents)) {
    return { label: 'Play a note', detail: '', cue: '', tone: 'muted', direction: 'center' };
  }
  const abs = Math.abs(cents);
  const direction: CentsVerdict['direction'] = abs <= 5 ? 'center' : cents > 0 ? 'sharp' : 'flat';
  const rounded = Math.round(abs);
  if (abs <= 5) {
    return { label: 'In tune', detail: 'right on', cue: 'hold it', tone: 'green', direction };
  }
  const word = direction === 'sharp' ? 'sharp' : 'flat';
  const cue = direction === 'sharp' ? 'ease down' : 'lift up';
  if (abs <= 15) {
    return { label: `A little ${word}`, detail: `${rounded}¢ ${word}`, cue, tone: 'amber', direction };
  }
  return { label: `${word.charAt(0).toUpperCase() + word.slice(1)}`, detail: `${rounded}¢ ${word}`, cue, tone: 'red', direction };
}

/** Turn an in-tune percentage into a friendly verdict for a whole session/run. */
export function describeInTunePercent(percent: number | null | undefined): { label: string; tone: TuneTone } {
  if (percent == null || Number.isNaN(percent)) return { label: 'No data yet', tone: 'muted' };
  const p = Math.round(percent);
  if (p >= 85) return { label: `${p}% in tune`, tone: 'green' };
  if (p >= 60) return { label: `${p}% in tune`, tone: 'amber' };
  return { label: `${p}% in tune`, tone: 'red' };
}

/** A 0–3 star rating from an in-tune percentage (Play-Along scoring). */
export function starsForPercent(percent: number | null | undefined): number {
  if (percent == null || Number.isNaN(percent)) return 0;
  if (percent >= 95) return 3;
  if (percent >= 85) return 2;
  if (percent >= 70) return 1;
  return 0;
}
