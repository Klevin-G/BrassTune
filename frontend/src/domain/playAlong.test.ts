import { describe, expect, it } from 'vitest';
import { PlayAlongGrader, centsGrade, summarizeGrades } from './playAlong';
import type { PitchFrame } from './types';

function frame(note: string | null, cents: number | null, confidence = 0.9): PitchFrame {
  return {
    timestamp_ms: 0,
    frequency_hz: note ? 440 : null,
    confidence,
    rms: 0.1,
    midi_note_float: null,
    nearest_midi: null,
    concert_note_name: note,
    concert_octave: 4,
    written_note_name: note,
    written_octave: 4,
    cents_deviation: cents,
    tuning_status: 'in_tune',
    instrument_id: 'trumpet',
    reference_pitch_hz: 440,
    is_valid_for_recording: true,
  };
}

describe('centsGrade', () => {
  it('classifies by absolute cents', () => {
    expect(centsGrade(3)).toBe('excellent');
    expect(centsGrade(-12)).toBe('good');
    expect(centsGrade(25)).toBe('close');
    expect(centsGrade(60)).toBe('off');
    expect(centsGrade(null)).toBe('missed');
  });
});

describe('PlayAlongGrader', () => {
  it('advances after sustaining the correct note and records average cents', () => {
    const grader = new PlayAlongGrader(['C', 'D'], { holdMs: 400, minSamples: 3 });
    // Sustain C at +10c for 500ms (frames every 100ms).
    for (let t = 0; t <= 500; t += 100) {
      grader.feed(frame('C', 10), t);
    }
    expect(grader.results.length).toBe(1);
    expect(grader.results[0].name).toBe('C');
    expect(grader.results[0].avgCents).toBeCloseTo(10, 5);
    expect(grader.results[0].grade).toBe('good');
    expect(grader.currentName).toBe('D');
  });

  it('does not advance on a brief touch that is not held', () => {
    const grader = new PlayAlongGrader(['C'], { holdMs: 400, minSamples: 3 });
    grader.feed(frame('C', 5), 0);
    grader.feed(frame('C', 5), 100); // only 100ms held
    expect(grader.results.length).toBe(0);
    expect(grader.currentName).toBe('C');
  });

  it('resets the hold when a different confident note is played', () => {
    const grader = new PlayAlongGrader(['C'], { holdMs: 400, minSamples: 3 });
    grader.feed(frame('C', 5), 0);
    grader.feed(frame('C', 5), 100);
    grader.feed(frame('E', 5), 200); // moved off target -> reset
    grader.feed(frame('C', 5), 300);
    grader.feed(frame('C', 5), 400); // only 100ms since reset
    expect(grader.results.length).toBe(0);
  });

  it('tolerates brief low-confidence dropouts without resetting', () => {
    const grader = new PlayAlongGrader(['C'], { holdMs: 400, minSamples: 3 });
    grader.feed(frame('C', 8), 0);
    grader.feed(frame(null, null, 0.1), 100); // silence blip
    grader.feed(frame('C', 8), 200);
    grader.feed(frame('C', 8), 500); // total window >= 400ms
    expect(grader.results.length).toBe(1);
    expect(grader.results[0].grade).toBe('good');
  });

  it('trims the attack transient so a scooped attack does not wreck the grade', () => {
    const grader = new PlayAlongGrader(['C'], { holdMs: 400, minSamples: 3, attackTrimMs: 120 });
    // Brass-style attack: badly sharp for the first ~100ms, then settles at +4c.
    grader.feed(frame('C', 45), 0);
    grader.feed(frame('C', 30), 80);
    grader.feed(frame('C', 4), 200);
    grader.feed(frame('C', 4), 320);
    grader.feed(frame('C', 4), 450);
    expect(grader.results.length).toBe(1);
    expect(grader.results[0].avgCents).toBeCloseTo(4, 5);
    expect(grader.results[0].grade).toBe('excellent');
  });

  it('uses the median so one detector blip cannot skew the score', () => {
    const grader = new PlayAlongGrader(['C'], { holdMs: 400, minSamples: 3, attackTrimMs: 0 });
    grader.feed(frame('C', 5), 0);
    grader.feed(frame('C', 5), 120);
    grader.feed(frame('C', 60), 240); // single wild blip
    grader.feed(frame('C', 5), 360);
    grader.feed(frame('C', 5), 480);
    expect(grader.results[0].avgCents).toBeCloseTo(5, 5);
    expect(grader.results[0].grade).toBe('excellent');
  });

  it('ignores low-confidence frames entirely', () => {
    const grader = new PlayAlongGrader(['C'], { holdMs: 300, minSamples: 3 });
    for (let t = 0; t <= 600; t += 100) grader.feed(frame('C', 5, 0.4), t); // below 0.65 gate
    expect(grader.results.length).toBe(0);
  });

  it('marks a skipped note as missed', () => {
    const grader = new PlayAlongGrader(['C', 'D'], { holdMs: 400 });
    grader.skip();
    expect(grader.results[0].grade).toBe('missed');
    expect(grader.results[0].avgCents).toBeNull();
    expect(grader.currentName).toBe('D');
  });

  it('completes and summarizes', () => {
    const grader = new PlayAlongGrader(['C', 'D'], { holdMs: 300, minSamples: 3 });
    for (const note of ['C', 'D']) {
      for (let t = 0; t <= 400; t += 100) grader.feed(frame(note, 4), t + (note === 'D' ? 1000 : 0));
    }
    expect(grader.done).toBe(true);
    const summary = summarizeGrades(grader.results);
    expect(summary.total).toBe(2);
    expect(summary.hit).toBe(2);
    expect(summary.inTune).toBe(2);
    expect(summary.inTunePercent).toBe(100);
    expect(summary.averageAbsCents).toBeCloseTo(4, 5);
  });
});
