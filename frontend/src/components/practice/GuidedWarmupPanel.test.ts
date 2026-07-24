import { describe, expect, it } from 'vitest';
import { updateWarmupTimer, type WarmupTimerState } from './GuidedWarmupPanel';

const stopped = (elapsedMilliseconds = 0): WarmupTimerState => ({
  elapsedMilliseconds,
  running: false,
  visible: true,
  activeSinceMilliseconds: null,
});

describe('guided warm-up timer', () => {
  it('pauses while hidden and resumes only from accumulated visible progress', () => {
    let state = updateWarmupTimer(stopped(), { type: 'start', visible: true }, 1_000);
    state = updateWarmupTimer(state, { type: 'tick' }, 11_000);
    expect(state.elapsedMilliseconds).toBe(10_000);

    state = updateWarmupTimer(state, { type: 'visibility', visible: false }, 12_500);
    expect(state.elapsedMilliseconds).toBe(11_500);
    expect(state.activeSinceMilliseconds).toBeNull();

    state = updateWarmupTimer(state, { type: 'tick' }, 112_500);
    state = updateWarmupTimer(state, { type: 'visibility', visible: false }, 115_000);
    expect(state.elapsedMilliseconds).toBe(11_500);

    state = updateWarmupTimer(state, { type: 'visibility', visible: true }, 120_000);
    state = updateWarmupTimer(state, { type: 'tick' }, 125_000);
    expect(state.elapsedMilliseconds).toBe(16_500);
  });

  it('handles repeated visible events without losing or double-counting time', () => {
    let state = updateWarmupTimer(stopped(20_000), { type: 'start', visible: true }, 5_000);
    state = updateWarmupTimer(state, { type: 'visibility', visible: true }, 7_000);
    state = updateWarmupTimer(state, { type: 'visibility', visible: true }, 9_000);
    state = updateWarmupTimer(state, { type: 'pause' }, 10_000);
    expect(state.elapsedMilliseconds).toBe(25_000);
    expect(state.running).toBe(false);
  });

  it('returns the current state for semantic timer no-ops', () => {
    const state = stopped(20_000);
    expect(updateWarmupTimer(state, { type: 'tick' }, 5_000)).toBe(state);
  });

  it('clamps completion, stops, and restarts a completed warm-up from zero', () => {
    let state = updateWarmupTimer(stopped(299_000), { type: 'start', visible: true }, 1_000);
    state = updateWarmupTimer(state, { type: 'tick' }, 5_000);
    expect(state).toMatchObject({
      elapsedMilliseconds: 300_000,
      running: false,
      activeSinceMilliseconds: null,
    });

    state = updateWarmupTimer(state, { type: 'start', visible: true }, 7_000);
    expect(state).toMatchObject({
      elapsedMilliseconds: 0,
      running: true,
      activeSinceMilliseconds: 7_000,
    });
  });
});
