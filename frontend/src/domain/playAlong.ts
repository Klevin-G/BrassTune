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
}

// Note-name spellings must match the detector's output set:
// ['C','C#','D','Eb','E','F','F#','G','Ab','A','Bb','B'].
export const EXERCISES: Exercise[] = [
  { id: 'cmaj', label: 'C major scale', detail: 'One octave, ascending', notes: ['C', 'D', 'E', 'F', 'G', 'A', 'B', 'C'] },
  { id: 'fmaj', label: 'F major scale', detail: 'One octave, ascending', notes: ['F', 'G', 'A', 'Bb', 'C', 'D', 'E', 'F'] },
  { id: 'gmaj', label: 'G major scale', detail: 'One octave, ascending', notes: ['G', 'A', 'B', 'C', 'D', 'E', 'F#', 'G'] },
  { id: 'arpeggio', label: 'C major arpeggio', detail: 'C · E · G · C', notes: ['C', 'E', 'G', 'C'] },
  { id: 'chromatic', label: 'Chromatic run', detail: 'C up to G', notes: ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G'] },
  { id: 'longtones', label: 'Long tones', detail: 'C · G · C — hold each note', notes: ['C', 'G', 'C'] },
];

export type CentsGrade = 'excellent' | 'good' | 'close' | 'off' | 'missed';

export function centsGrade(avgCents: number | null): CentsGrade {
  if (avgCents == null || Number.isNaN(avgCents)) return 'missed';
  const abs = Math.abs(avgCents);
  if (abs <= 5) return 'excellent';
  if (abs <= 15) return 'good';
  if (abs <= 30) return 'close';
  return 'off';
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
  const inTune = played.filter((r) => r.grade === 'excellent' || r.grade === 'good').length;
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
  private idx = 0;
  private firstMatchTs: number | null = null;
  private lastNow = 0;
  private centsBuf: { ts: number; cents: number }[] = [];
  results: NoteGrade[] = [];

  constructor(notes: string[], options: { holdMs?: number; minConfidence?: number; minSamples?: number; attackTrimMs?: number } = {}) {
    this.notes = notes;
    this.holdMs = options.holdMs ?? 450;
    this.minConfidence = options.minConfidence ?? 0.65;
    this.minSamples = options.minSamples ?? 5;
    this.attackTrimMs = options.attackTrimMs ?? 120;
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
    this.results.push({ name: this.notes[this.idx], avgCents: rounded, samples: this.centsBuf.length, grade: centsGrade(rounded) });
    this.idx += 1;
    this.firstMatchTs = null;
    this.centsBuf = [];
  }

  /** Mark the current target as missed and advance (e.g. user pressed Skip). */
  skip(): void {
    if (!this.done) this.finalize(false);
  }

  feed(frame: PitchFrame, nowMs: number): GraderSnapshot {
    this.lastNow = nowMs;
    if (!this.done) {
      const target = this.notes[this.idx];
      const confident = frame.confidence >= this.minConfidence && frame.frequency_hz != null;
      const matches = confident && frame.written_note_name === target && frame.cents_deviation != null;
      if (matches) {
        if (this.firstMatchTs == null) this.firstMatchTs = nowMs;
        this.centsBuf.push({ ts: nowMs, cents: frame.cents_deviation as number });
        if (nowMs - this.firstMatchTs >= this.holdMs && this.centsBuf.length >= this.minSamples) {
          this.finalize(true);
        }
      } else if (confident && frame.written_note_name && frame.written_note_name !== target) {
        // Player is sustaining a different note — reset the current hold.
        this.firstMatchTs = null;
        this.centsBuf = [];
      }
    }
    return this.snapshot(frame);
  }

  snapshot(frame?: PitchFrame): GraderSnapshot {
    const heldFraction = this.firstMatchTs == null ? 0 : Math.min(1, (this.lastNow - this.firstMatchTs) / this.holdMs);
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
