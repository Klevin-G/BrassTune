import { describe, expect, it } from 'vitest';
import metronomeCases from '../../../fixtures/metronome_cases.json';
import { buildScheduledTicks, clampBpm, nextRampBpm, normalizeTimeSignature, secondsPerTick, tapTempoBpm, ticksPerBar, timingStats, type Subdivision } from './metronome';

describe('metronome timing helpers', () => {
  it('bounds tempo and time signatures', () => {
    expect(clampBpm(10)).toBe(20);
    expect(clampBpm(360)).toBe(300);
    expect(normalizeTimeSignature(7, 8)).toEqual({ numerator: 7, denominator: 8 });
    expect(normalizeTimeSignature(99, 3)).toEqual({ numerator: 16, denominator: 4 });
  });

  it('schedules accented downbeats with subdivision timing', () => {
    const signature = { numerator: 3, denominator: 4 };
    const ticks = buildScheduledTicks({ startTime: 10, bpm: 120, signature, subdivision: 'eighth', bars: 2 });
    expect(ticks).toHaveLength(12);
    expect(ticksPerBar(signature, 'eighth')).toBe(6);
    expect(secondsPerTick(120, signature, 'eighth')).toBeCloseTo(0.25);
    expect(ticks[0]).toMatchObject({ beatIndex: 0, subdivisionIndex: 0, accented: true });
    expect(ticks[2]).toMatchObject({ beatIndex: 1, subdivisionIndex: 0, accented: false });
    expect(ticks[6]).toMatchObject({ beatIndex: 0, subdivisionIndex: 0, accented: true });
  });

  it('treats BPM as the selected denominator beat in compound and cut time', () => {
    const sevenEight = { numerator: 7, denominator: 8 };
    for (const metronomeCase of metronomeCases.cases) {
      expect(
        secondsPerTick(
          metronomeCase.bpm,
          { numerator: metronomeCase.numerator, denominator: metronomeCase.denominator },
          metronomeCase.subdivision as Subdivision,
        ),
        metronomeCase.name,
      ).toBeCloseTo(metronomeCase.expected_seconds);
    }

    const ticks = buildScheduledTicks({ startTime: 0, bpm: 120, signature: sevenEight, subdivision: 'eighth', bars: 1 });
    expect(ticks).toHaveLength(14);
    expect(ticks[1].time).toBeCloseTo(0.25);
    expect(ticks[2].time).toBeCloseTo(0.5);
  });

  it('derives tap tempo from recent taps', () => {
    expect(tapTempoBpm([0])).toBeNull();
    expect(tapTempoBpm([0, 500, 1000, 1500])).toBe(120);
  });

  it('ramps tempo without overshooting and reports jitter', () => {
    expect(nextRampBpm(100, 112, 5)).toBe(105);
    expect(nextRampBpm(110, 112, 5)).toBe(112);
    expect(nextRampBpm(112, 100, 7)).toBe(105);
    expect(timingStats([0, 0.5, 1.01, 1.49])).toEqual({ intervals: 3, averageMs: expect.any(Number), maxJitterMs: expect.any(Number) });
  });
});
