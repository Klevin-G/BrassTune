import { describe, expect, it } from 'vitest';
import scorerContract from '../../../fixtures/play_along_contract.json';
import {
  EXERCISES,
  DEFAULT_PLAY_ALONG_ATTACK_TRIM_MS,
  DEFAULT_PLAY_ALONG_HOLD_MS,
  DEFAULT_PLAY_ALONG_MAX_DROPOUT_MS,
  DEFAULT_PLAY_ALONG_MIN_CONFIDENCE,
  DEFAULT_PLAY_ALONG_MIN_SAMPLES,
  MAJOR_SCALES,
  MINOR_SCALES,
  OTHER_EXERCISES,
  PLAY_ALONG_ACCEPTED_CENTS,
  PLAY_ALONG_CENTERED_CENTS,
  PlayAlongGrader,
  centsGrade,
  isAcceptedPlayAlongCents,
  normalizePitchClass,
  samePitchClass,
  summarizeGrades,
} from './playAlong';
import type { PitchFrame } from './types';
import { starsForPercent } from './tuningLanguage';

function frame(note: string | null, cents: number | null, confidence = 0.99): PitchFrame {
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
    expect(centsGrade(-12)).toBe('close');
    expect(centsGrade(25)).toBe('off');
    expect(centsGrade(60)).toBe('off');
    expect(centsGrade(null)).toBe('missed');
  });

  it('loads rating, acceptance, and star thresholds from the portable contract', () => {
    expect({
      centered_cents_inclusive: PLAY_ALONG_CENTERED_CENTS,
      accepted_cents_inclusive: PLAY_ALONG_ACCEPTED_CENTS,
      hold_ms: DEFAULT_PLAY_ALONG_HOLD_MS,
      minimum_confidence: DEFAULT_PLAY_ALONG_MIN_CONFIDENCE,
      minimum_samples: DEFAULT_PLAY_ALONG_MIN_SAMPLES,
      attack_trim_ms: DEFAULT_PLAY_ALONG_ATTACK_TRIM_MS,
      maximum_dropout_ms: DEFAULT_PLAY_ALONG_MAX_DROPOUT_MS,
    }).toEqual(scorerContract.policy);

    for (const testCase of scorerContract.rating_cases) {
      expect(centsGrade(testCase.cents), testCase.name).toBe(testCase.expected_rating);
      expect(isAcceptedPlayAlongCents(testCase.cents), testCase.name).toBe(testCase.expected_accepted);
      expect(testCase.cents != null && Math.abs(testCase.cents) <= PLAY_ALONG_CENTERED_CENTS, testCase.name).toBe(testCase.expected_centered);
    }
    for (const testCase of scorerContract.star_cases) {
      expect(starsForPercent(testCase.in_tune_percent), String(testCase.in_tune_percent)).toBe(testCase.expected_stars);
    }
    for (const testCase of scorerContract.summary_cases) {
      const results = testCase.ratings.map((rating, index) => ({
        name: `N${index}`,
        avgCents: rating.cents,
        samples: rating.cents == null ? 0 : 5,
        grade: rating.rating as ReturnType<typeof centsGrade>,
      }));
      const summary = summarizeGrades(results);
      expect(summary, testCase.name).toEqual({
        total: testCase.expected_total,
        hit: testCase.expected_hit,
        inTune: testCase.expected_in_tune,
        inTunePercent: testCase.expected_in_tune_percent,
        averageAbsCents: testCase.expected_average_abs_cents,
      });
      expect(starsForPercent(summary.inTunePercent), testCase.name).toBe(testCase.expected_stars);
    }
  });
});

describe('exercise catalog', () => {
  const expectedMajorScales: Record<string, string[]> = {
    cmaj: ['C', 'D', 'E', 'F', 'G', 'A', 'B', 'C'],
    dbmaj: ['Db', 'Eb', 'F', 'Gb', 'Ab', 'Bb', 'C', 'Db'],
    dmaj: ['D', 'E', 'F#', 'G', 'A', 'B', 'C#', 'D'],
    ebmaj: ['Eb', 'F', 'G', 'Ab', 'Bb', 'C', 'D', 'Eb'],
    emaj: ['E', 'F#', 'G#', 'A', 'B', 'C#', 'D#', 'E'],
    fmaj: ['F', 'G', 'A', 'Bb', 'C', 'D', 'E', 'F'],
    fsmaj: ['F#', 'G#', 'A#', 'B', 'C#', 'D#', 'E#', 'F#'],
    gmaj: ['G', 'A', 'B', 'C', 'D', 'E', 'F#', 'G'],
    abmaj: ['Ab', 'Bb', 'C', 'Db', 'Eb', 'F', 'G', 'Ab'],
    amaj: ['A', 'B', 'C#', 'D', 'E', 'F#', 'G#', 'A'],
    bbmaj: ['Bb', 'C', 'D', 'Eb', 'F', 'G', 'A', 'Bb'],
    bmaj: ['B', 'C#', 'D#', 'E', 'F#', 'G#', 'A#', 'B'],
  };

  const expectedMinorScales: Record<string, string[]> = {
    cmin: ['C', 'D', 'Eb', 'F', 'G', 'Ab', 'Bb', 'C'],
    csmin: ['C#', 'D#', 'E', 'F#', 'G#', 'A', 'B', 'C#'],
    dmin: ['D', 'E', 'F', 'G', 'A', 'Bb', 'C', 'D'],
    ebmin: ['Eb', 'F', 'Gb', 'Ab', 'Bb', 'Cb', 'Db', 'Eb'],
    emin: ['E', 'F#', 'G', 'A', 'B', 'C', 'D', 'E'],
    fmin: ['F', 'G', 'Ab', 'Bb', 'C', 'Db', 'Eb', 'F'],
    fsmin: ['F#', 'G#', 'A', 'B', 'C#', 'D', 'E', 'F#'],
    gmin: ['G', 'A', 'Bb', 'C', 'D', 'Eb', 'F', 'G'],
    gsmin: ['G#', 'A#', 'B', 'C#', 'D#', 'E', 'F#', 'G#'],
    amin: ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'A'],
    bbmin: ['Bb', 'C', 'Db', 'Eb', 'F', 'Gb', 'Ab', 'Bb'],
    bmin: ['B', 'C#', 'D', 'E', 'F#', 'G', 'A', 'B'],
  };

  it('contains 12 major, 12 natural minor, and three existing other exercises', () => {
    expect(MAJOR_SCALES).toHaveLength(12);
    expect(MINOR_SCALES).toHaveLength(12);
    expect(OTHER_EXERCISES).toHaveLength(3);
    expect(EXERCISES).toHaveLength(27);
    expect(new Set(EXERCISES.map((exercise) => exercise.id)).size).toBe(EXERCISES.length);
    expect(MAJOR_SCALES.find((exercise) => exercise.id === 'cmaj')?.notes).toEqual(['C', 'D', 'E', 'F', 'G', 'A', 'B', 'C']);
    expect(['fmaj', 'gmaj', 'arpeggio', 'chromatic', 'longtones'].every((id) => EXERCISES.some((exercise) => exercise.id === id))).toBe(true);
  });

  it('preserves the exact diatonic spellings for every scale', () => {
    expect(Object.fromEntries(MAJOR_SCALES.map((scale) => [scale.id, scale.notes]))).toEqual(expectedMajorScales);
    expect(Object.fromEntries(MINOR_SCALES.map((scale) => [scale.id, scale.notes]))).toEqual(expectedMinorScales);
  });

  it.each([
    ['major', MAJOR_SCALES, [0, 2, 4, 5, 7, 9, 11, 0]],
    ['minor', MINOR_SCALES, [0, 2, 3, 5, 7, 8, 10, 0]],
  ] as const)('uses the correct %s scale formula and closes the octave', (_name, scales, formula) => {
    for (const scale of scales) {
      expect(scale.notes).toHaveLength(8);
      const root = normalizePitchClass(scale.notes[0]);
      expect(root).not.toBeNull();
      expect(scale.notes.map((note) => ((normalizePitchClass(note) as number) - (root as number) + 12) % 12)).toEqual(formula);
      expect(samePitchClass(scale.notes[0], scale.notes[scale.notes.length - 1])).toBe(true);
    }
  });

  it('normalizes enharmonic spellings used by written scales', () => {
    expect(samePitchClass('Db', 'C#')).toBe(true);
    expect(samePitchClass('E#', 'F')).toBe(true);
    expect(samePitchClass('Cb', 'B')).toBe(true);
    expect(samePitchClass('Gb', 'F#')).toBe(true);
    expect(samePitchClass('D♭', 'C♯')).toBe(true);
    expect(samePitchClass('F♯', 'Gb')).toBe(true);
    expect(normalizePitchClass('not-a-note')).toBeNull();
  });
});

describe('PlayAlongGrader', () => {
  it('replays every portable temporal timeline at its declared checkpoints', () => {
    expect(scorerContract.temporal_evidence_kind).toContain('synthetic deterministic pitch-frame timelines');

    for (const testCase of scorerContract.temporal_cases) {
      const grader = new PlayAlongGrader(testCase.notes);
      const checkpoints = new Map(testCase.checkpoints.map((checkpoint) => [checkpoint.after_frame_index, checkpoint]));

      testCase.frames.forEach((testFrame, frameIndex) => {
        const snapshot = grader.feed(frame(testFrame.written_note, testFrame.cents, testFrame.confidence), testFrame.timestamp_ms);
        const checkpoint = checkpoints.get(frameIndex);
        if (!checkpoint) return;
        expect(snapshot.currentName, `${testCase.name}: current note after frame ${frameIndex}`).toBe(checkpoint.expected_current_note);
        expect(snapshot.heldFraction * grader.holdMs, `${testCase.name}: held ms after frame ${frameIndex}`).toBeCloseTo(
          checkpoint.expected_held_ms,
          8,
        );
        expect(snapshot.results, `${testCase.name}: result count after frame ${frameIndex}`).toHaveLength(checkpoint.expected_result_count);
        expect(snapshot.done, `${testCase.name}: done after frame ${frameIndex}`).toBe(checkpoint.expected_done);
      });

      expect(
        grader.results.map((result) => ({
          name: result.name,
          median_cents: result.avgCents,
          sample_count: result.samples,
          rating: result.grade,
        })),
        testCase.name,
      ).toEqual(testCase.expected_results);
    }
  });

  it('uses a 2-second default and does not advance before the full hold', () => {
    const grader = new PlayAlongGrader(['C']);
    expect(grader.holdMs).toBe(DEFAULT_PLAY_ALONG_HOLD_MS);

    for (let t = 0; t <= 1_750; t += 250) grader.feed(frame('C', 5), t);
    const justBefore = grader.feed(frame('C', 5), 1_999);

    expect(justBefore.heldFraction).toBeCloseTo(1_999 / 2_000, 5);
    expect(grader.results).toEqual([]);
    expect(grader.currentName).toBe('C');
  });

  it('advances once the default 2-second hold is reached', () => {
    const grader = new PlayAlongGrader(['C', 'D']);
    for (let t = 0; t <= 2_000; t += 250) grader.feed(frame('C', 5), t);

    expect(grader.results).toHaveLength(1);
    expect(grader.results[0].name).toBe('C');
    expect(grader.currentName).toBe('D');
  });

  it('honors an explicit hold override and records average cents', () => {
    const grader = new PlayAlongGrader(['C', 'D'], { holdMs: 400, minSamples: 3 });
    expect(grader.holdMs).toBe(400);
    // Sustain C at +10c for 500ms (frames every 100ms).
    for (let t = 0; t <= 500; t += 100) {
      grader.feed(frame('C', 10), t);
    }
    expect(grader.results.length).toBe(1);
    expect(grader.results[0].name).toBe('C');
    expect(grader.results[0].avgCents).toBeCloseTo(10, 5);
    expect(grader.results[0].grade).toBe('close');
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
    expect(grader.snapshot().heldFraction).toBeCloseTo(0.25, 5);
  });

  it('grades detector canonical names against enharmonic written spellings', () => {
    const grader = new PlayAlongGrader(['E#'], { holdMs: 300, minSamples: 3 });
    for (let t = 0; t <= 400; t += 100) grader.feed(frame('F', 4), t);
    expect(grader.done).toBe(true);
    expect(grader.results[0].name).toBe('E#');
    expect(grader.results[0].grade).toBe('excellent');
  });

  it('tolerates brief low-confidence dropouts without resetting', () => {
    const grader = new PlayAlongGrader(['C'], { holdMs: 400, minSamples: 3 });
    grader.feed(frame('C', 8), 0);
    grader.feed(frame(null, null, 0.1), 100); // silence blip
    grader.feed(frame('C', 8), 200);
    grader.feed(frame('C', 8), 400);
    grader.feed(frame('C', 8), 600); // 400ms of confirmed matching time
    expect(grader.results.length).toBe(1);
    expect(grader.results[0].grade).toBe('close');
  });

  it('pauses visible held progress during a tolerated detector dropout', () => {
    const grader = new PlayAlongGrader(['C'], { holdMs: 400, minSamples: 3, maximumDropoutMs: 250 });
    grader.feed(frame('C', 4), 0);
    const beforeDropout = grader.feed(frame('C', 4), 100);
    const duringDropout = grader.feed(frame(null, null, 0.1), 200);
    const afterResume = grader.feed(frame('C', 4), 250);

    expect(beforeDropout.heldFraction).toBeCloseTo(0.25, 5);
    expect(duringDropout.heldFraction).toBeCloseTo(0.25, 5);
    expect(afterResume.heldFraction).toBeCloseTo(0.25, 5);
    expect(grader.results).toEqual([]);
  });

  it('resets a stale hold after the native 250ms dropout grace', () => {
    const grader = new PlayAlongGrader(['C'], { holdMs: 400, minSamples: 3, maximumDropoutMs: 250 });
    grader.feed(frame('C', 4), 0);
    grader.feed(frame('C', 4), 100);
    const afterGap = grader.feed(frame('C', 4), 500);

    expect(afterGap.heldFraction).toBe(0);
    for (let t = 600; t <= 800; t += 100) grader.feed(frame('C', 4), t);
    expect(grader.done).toBe(false);
    expect(grader.results).toEqual([]);
  });

  it('does not advance until the matching note is within the accepted 15-cent window', () => {
    const grader = new PlayAlongGrader(['C'], { holdMs: 300, minSamples: 3 });
    grader.feed(frame('C', 16), 0);
    grader.feed(frame('C', 16), 100);
    grader.feed(frame('C', 16), 200);
    grader.feed(frame('C', 16), 300);
    expect(grader.results).toEqual([]);
    expect(grader.snapshot().heldFraction).toBe(0);

    for (let timestamp = 400; timestamp <= 700; timestamp += 100) {
      grader.feed(frame('C', 15), timestamp);
    }
    expect(grader.done).toBe(true);
    expect(grader.results[0].grade).toBe('close');
  });

  it('resets while receiving prolonged low-confidence frames', () => {
    const grader = new PlayAlongGrader(['C'], { holdMs: 400, minSamples: 3, maximumDropoutMs: 250 });
    grader.feed(frame('C', 4), 0);
    grader.feed(frame('C', 4), 100);
    grader.feed(frame(null, null, 0.1), 200);
    const afterSilence = grader.feed(frame(null, null, 0.1), 400);

    expect(afterSilence.heldFraction).toBe(0);
    expect(grader.results).toEqual([]);
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
    let snapshot = grader.snapshot();
    for (let t = 0; t <= 600; t += 100) snapshot = grader.feed(frame('C', 0, 0.9), t); // centered, but below the 95% scoring gate
    expect(grader.results.length).toBe(0);
    expect(snapshot.heldFraction).toBe(0);
    expect(snapshot.detectedName).toBeNull();
    expect(snapshot.detectedCents).toBeNull();
  });

  it.each([
    {
      name: 'explicitly invalid',
      patch: { is_valid_for_recording: false, save_eligibility_reason: 'unstable/no pitch lock' },
    },
    {
      name: 'unstable',
      patch: { tuning_status: 'unstable' as const },
    },
    {
      name: 'silence',
      patch: { tuning_status: 'silence' as const },
    },
  ])('does not award an excellent grade to $name pitch frames', ({ patch }) => {
    const grader = new PlayAlongGrader(['C'], { holdMs: 300, minSamples: 3 });
    let snapshot = grader.snapshot();
    for (let timestamp = 0; timestamp <= 600; timestamp += 100) {
      snapshot = grader.feed({ ...frame('C', 0), ...patch }, timestamp);
    }

    expect(grader.results).toEqual([]);
    expect(snapshot.heldFraction).toBe(0);
    expect(snapshot.detectedName).toBeNull();
    expect(snapshot.detectedCents).toBeNull();
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
