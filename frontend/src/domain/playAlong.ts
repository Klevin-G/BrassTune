import type { PitchFrame } from './types';

// A play-along exercise is a sequence of *written* pitch-class names (what the
// player reads on their instrument). Grading matches the detector's
// written_note_name by pitch class + cents, so a single set of exercises works
// for every brass instrument regardless of transposition or clef/octave.
export interface Exercise {
  id: string;
  label: string;
  detail: string;
  notes: string[];
  group: 'major' | 'minor' | 'other';
}

const PITCH_CLASS: Record<string, number> = {
  C: 0, 'C#': 1, Db: 1, D: 2, 'D#': 3, Eb: 3, E: 4, 'E#': 5, Fb: 4,
  F: 5, 'F#': 6, Gb: 6, G: 7, 'G#': 8, Ab: 8, A: 9, 'A#': 10, Bb: 10,
  B: 11, Cb: 11, 'B#': 0,
};

/** Compare written spellings enharmonically with the detector's canonical names. */
export function normalizePitchClass(note: string | null | undefined): number | null {
  if (!note) return null;
  const normalized = note.trim().replace(/♯/g, '#').replace(/♭/g, 'b');
  return PITCH_CLASS[normalized] ?? null;
}

export function samePitchClass(a: string | null | undefined, b: string | null | undefined): boolean {
  const left = normalizePitchClass(a);
  return left != null && left === normalizePitchClass(b);
}

// Keep musically correct written spellings for display. The grader compares by
// pitch class, so detector output such as F still matches E# in F# major.
export const MAJOR_SCALES: Exercise[] = [
  ['cmaj', 'C', ['C', 'D', 'E', 'F', 'G', 'A', 'B', 'C']],
  ['dbmaj', 'D♭', ['Db', 'Eb', 'F', 'Gb', 'Ab', 'Bb', 'C', 'Db']],
  ['dmaj', 'D', ['D', 'E', 'F#', 'G', 'A', 'B', 'C#', 'D']],
  ['ebmaj', 'E♭', ['Eb', 'F', 'G', 'Ab', 'Bb', 'C', 'D', 'Eb']],
  ['emaj', 'E', ['E', 'F#', 'G#', 'A', 'B', 'C#', 'D#', 'E']],
  ['fmaj', 'F', ['F', 'G', 'A', 'Bb', 'C', 'D', 'E', 'F']],
  ['fsmaj', 'F♯', ['F#', 'G#', 'A#', 'B', 'C#', 'D#', 'E#', 'F#']],
  ['gmaj', 'G', ['G', 'A', 'B', 'C', 'D', 'E', 'F#', 'G']],
  ['abmaj', 'A♭', ['Ab', 'Bb', 'C', 'Db', 'Eb', 'F', 'G', 'Ab']],
  ['amaj', 'A', ['A', 'B', 'C#', 'D', 'E', 'F#', 'G#', 'A']],
  ['bbmaj', 'B♭', ['Bb', 'C', 'D', 'Eb', 'F', 'G', 'A', 'Bb']],
  ['bmaj', 'B', ['B', 'C#', 'D#', 'E', 'F#', 'G#', 'A#', 'B']],
].map(([id, root, notes]) => ({ id: id as string, label: `${root} major`, detail: 'One octave, ascending', notes: notes as string[], group: 'major' }));

export const MINOR_SCALES: Exercise[] = [
  ['cmin', 'C', ['C', 'D', 'Eb', 'F', 'G', 'Ab', 'Bb', 'C']],
  ['csmin', 'C♯', ['C#', 'D#', 'E', 'F#', 'G#', 'A', 'B', 'C#']],
  ['dmin', 'D', ['D', 'E', 'F', 'G', 'A', 'Bb', 'C', 'D']],
  ['ebmin', 'E♭', ['Eb', 'F', 'Gb', 'Ab', 'Bb', 'Cb', 'Db', 'Eb']],
  ['emin', 'E', ['E', 'F#', 'G', 'A', 'B', 'C', 'D', 'E']],
  ['fmin', 'F', ['F', 'G', 'Ab', 'Bb', 'C', 'Db', 'Eb', 'F']],
  ['fsmin', 'F♯', ['F#', 'G#', 'A', 'B', 'C#', 'D', 'E', 'F#']],
  ['gmin', 'G', ['G', 'A', 'Bb', 'C', 'D', 'Eb', 'F', 'G']],
  ['gsmin', 'G♯', ['G#', 'A#', 'B', 'C#', 'D#', 'E', 'F#', 'G#']],
  ['amin', 'A', ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'A']],
  ['bbmin', 'B♭', ['Bb', 'C', 'Db', 'Eb', 'F', 'Gb', 'Ab', 'Bb']],
  ['bmin', 'B', ['B', 'C#', 'D', 'E', 'F#', 'G', 'A', 'B']],
].map(([id, root, notes]) => ({ id: id as string, label: `${root} minor`, detail: 'Natural minor · one octave, ascending', notes: notes as string[], group: 'minor' }));

export const OTHER_EXERCISES: Exercise[] = [
  { id: 'arpeggio', label: 'C major arpeggio', detail: 'C · E · G · C', notes: ['C', 'E', 'G', 'C'], group: 'other' },
  { id: 'chromatic', label: 'Chromatic run', detail: 'C up to G', notes: ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G'], group: 'other' },
  { id: 'longtones', label: 'Long tones', detail: 'C · G · C — hold each note', notes: ['C', 'G', 'C'], group: 'other' },
];

export const EXERCISES: Exercise[] = [...MAJOR_SCALES, ...MINOR_SCALES, ...OTHER_EXERCISES];

export type CentsGrade = 'excellent' | 'good' | 'close' | 'off' | 'missed';

/** Portable Play-Along contract; mirrored in fixtures/play_along_contract.json. */
export const PLAY_ALONG_CENTERED_CENTS = 5;
export const PLAY_ALONG_ACCEPTED_CENTS = 15;
export const DEFAULT_PLAY_ALONG_HOLD_MS = 2_000;
export const DEFAULT_PLAY_ALONG_MIN_CONFIDENCE = 0.65;
export const DEFAULT_PLAY_ALONG_MIN_SAMPLES = 5;
export const DEFAULT_PLAY_ALONG_ATTACK_TRIM_MS = 120;
export const DEFAULT_PLAY_ALONG_MAX_DROPOUT_MS = 250;

export function centsGrade(avgCents: number | null): CentsGrade {
  if (avgCents == null || Number.isNaN(avgCents)) return 'missed';
  const abs = Math.abs(avgCents);
  if (abs <= PLAY_ALONG_CENTERED_CENTS) return 'excellent';
  if (abs <= PLAY_ALONG_ACCEPTED_CENTS) return 'close';
  return 'off';
}

export function isAcceptedPlayAlongCents(cents: number | null | undefined): boolean {
  return cents != null && Number.isFinite(cents) && Math.abs(cents) <= PLAY_ALONG_ACCEPTED_CENTS;
}

export interface NoteGrade {
  name: string;
  avgCents: number | null;
  samples: number;
  grade: CentsGrade;
}

export interface GraderSnapshot {
  index: number;
  currentName: string | null;
  heldFraction: number;
  detectedName: string | null;
  detectedCents: number | null;
  done: boolean;
  results: NoteGrade[];
}

export interface GradeSummary {
  total: number;
  hit: number;
  inTune: number;
  inTunePercent: number;
  averageAbsCents: number | null;
}

export function summarizeGrades(results: NoteGrade[]): GradeSummary {
  const total = results.length;
  const played = results.filter((r) => r.avgCents != null);
  // "In tune" means centered within +/-5 cents. A close note is accepted so
  // practice can continue, but it is not promoted into the centered metric.
  const inTune = played.filter((r) => r.grade === 'excellent').length;
  const absSum = played.reduce((sum, r) => sum + Math.abs(r.avgCents as number), 0);
  return {
    total,
    hit: played.length,
    inTune,
    inTunePercent: total > 0 ? Math.round((inTune / total) * 100) : 0,
    averageAbsCents: played.length > 0 ? Math.round((absSum / played.length) * 10) / 10 : null,
  };
}

function median(values: number[]): number {
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/**
 * Self-paced grading engine. Feed it live pitch frames; when the player sustains
 * the correct pitch class for `holdMs`, the note is scored and the target
 * advances. Playing a different confident note resets the current hold; brief
 * silence/low-confidence dropouts are tolerated.
 *
 * Scoring is intonation-grade accurate: the attack transient (first
 * `attackTrimMs` of the held note, where brass pitch naturally scoops) is
 * excluded, and the score is the MEDIAN cents of the sustained portion —
 * robust to detector blips and vibrato extremes in a way a mean is not.
 */
export class PlayAlongGrader {
  readonly notes: string[];
  holdMs: number;
  minConfidence: number;
  minSamples: number;
  attackTrimMs: number;
  maximumDropoutMs: number;
  private idx = 0;
  private firstMatchTs: number | null = null;
  private lastMatchTs: number | null = null;
  private previousFrameTs: number | null = null;
  private previousFrameMatched = false;
  private heldMs = 0;
  private centsBuf: { ts: number; cents: number }[] = [];
  results: NoteGrade[] = [];

  constructor(notes: string[], options: { holdMs?: number; minConfidence?: number; minSamples?: number; attackTrimMs?: number; maximumDropoutMs?: number } = {}) {
    this.notes = notes;
    this.holdMs = options.holdMs ?? DEFAULT_PLAY_ALONG_HOLD_MS;
    this.minConfidence = options.minConfidence ?? DEFAULT_PLAY_ALONG_MIN_CONFIDENCE;
    this.minSamples = options.minSamples ?? DEFAULT_PLAY_ALONG_MIN_SAMPLES;
    this.attackTrimMs = options.attackTrimMs ?? DEFAULT_PLAY_ALONG_ATTACK_TRIM_MS;
    this.maximumDropoutMs = Math.max(0, options.maximumDropoutMs ?? DEFAULT_PLAY_ALONG_MAX_DROPOUT_MS);
  }

  get done(): boolean {
    return this.idx >= this.notes.length;
  }

  get currentName(): string | null {
    return this.done ? null : this.notes[this.idx];
  }

  private finalize(hit: boolean): void {
    let scored: number | null = null;
    if (hit && this.centsBuf.length && this.firstMatchTs != null) {
      // Score the sustain, not the attack: trim the first attackTrimMs unless
      // that would leave too few samples to be trustworthy.
      const start = this.firstMatchTs;
      const sustained = this.centsBuf.filter((entry) => entry.ts - start >= this.attackTrimMs);
      const source = sustained.length >= Math.min(this.minSamples, 3) ? sustained : this.centsBuf;
      scored = median(source.map((entry) => entry.cents));
    }
    const rounded = scored == null ? null : Math.round(scored * 10) / 10;
    if (hit && !isAcceptedPlayAlongCents(scored)) {
      // The correct written note was held, but its stable post-attack median
      // never entered the accepted window. Keep the same target and require a
      // fresh two-second centered/close sustain.
      this.resetHold();
      return;
    }
    this.results.push({ name: this.notes[this.idx], avgCents: rounded, samples: this.centsBuf.length, grade: centsGrade(rounded) });
    this.idx += 1;
    this.resetHold();
  }

  private resetHold(): void {
    this.firstMatchTs = null;
    this.lastMatchTs = null;
    this.previousFrameTs = null;
    this.previousFrameMatched = false;
    this.heldMs = 0;
    this.centsBuf = [];
  }

  /** Mark the current target as missed and advance (e.g. user pressed Skip). */
  skip(): void {
    if (!this.done) this.finalize(false);
  }

  feed(frame: PitchFrame, nowMs: number): GraderSnapshot {
    if (!this.done) {
      const target = this.notes[this.idx];
      const confident = frame.confidence >= this.minConfidence && frame.frequency_hz != null;
      const matchesPitchClass = samePitchClass(frame.written_note_name, target);
      const matches = confident && matchesPitchClass && frame.cents_deviation != null && Number.isFinite(frame.cents_deviation);
      if (matches) {
        if (this.lastMatchTs != null && nowMs - this.lastMatchTs > this.maximumDropoutMs) {
          this.resetHold();
        }
        if (this.firstMatchTs == null) this.firstMatchTs = nowMs;
        if (this.previousFrameMatched && this.previousFrameTs != null) {
          this.heldMs += Math.max(0, nowMs - this.previousFrameTs);
        }
        this.lastMatchTs = nowMs;
        this.previousFrameTs = nowMs;
        this.previousFrameMatched = true;
        this.centsBuf.push({ ts: nowMs, cents: frame.cents_deviation as number });
        if (this.heldMs >= this.holdMs && this.centsBuf.length >= this.minSamples) {
          this.finalize(true);
        }
      } else if (confident && frame.written_note_name && !matchesPitchClass) {
        // A different confident note is contrary evidence. A same-note attack
        // may begin outside the window; its post-attack median is validated
        // before advancement.
        this.resetHold();
      } else {
        // A brief detector dropout pauses confirmed hold time. It does not fill
        // the ring, but it also does not erase progress unless the grace period
        // is exceeded.
        this.previousFrameTs = nowMs;
        this.previousFrameMatched = false;
        if (this.lastMatchTs != null && nowMs - this.lastMatchTs > this.maximumDropoutMs) {
          // Match native behavior: never let a stale hold bridge more than the
          // configured grace period of silence, low confidence, or missing cents.
          this.resetHold();
        }
      }
    }
    return this.snapshot(frame);
  }

  snapshot(frame?: PitchFrame): GraderSnapshot {
    const heldFraction = this.firstMatchTs == null ? 0 : Math.min(1, this.heldMs / this.holdMs);
    return {
      index: this.idx,
      currentName: this.currentName,
      heldFraction,
      detectedName: frame?.written_note_name ?? null,
      detectedCents: frame?.cents_deviation ?? null,
      done: this.done,
      results: this.results,
    };
  }
}
