import { describe, expect, it } from 'vitest';
import { droneRecentHref, droneSelectionFromSearch } from './DroneIntervalPanel';

describe('drone recent selection', () => {
  it('persists both the written note and interval in a recent route', () => {
    const selection = { writtenMidi: 66, interval: 7 };
    const href = droneRecentHref(selection);

    expect(href).toBe('/practice?tool=drone&midi=66&interval=7');
    expect(droneSelectionFromSearch(new URLSearchParams(href.split('?')[1]))).toEqual(selection);
  });

  it('restores the full written range, migrates legacy pitch-class links, and fails closed for malformed recents', () => {
    expect(droneSelectionFromSearch(new URLSearchParams('midi=36&interval=2'))).toEqual({ writtenMidi: 36, interval: 2 });
    expect(droneSelectionFromSearch(new URLSearchParams('midi=84&interval=12'))).toEqual({ writtenMidi: 84, interval: 12 });
    expect(droneSelectionFromSearch(new URLSearchParams('note=Eb&interval=4'))).toEqual({ writtenMidi: 63, interval: 4 });
    expect(droneSelectionFromSearch(new URLSearchParams('midi=85&note=H&interval=99'))).toEqual({ writtenMidi: 70, interval: 0 });
  });
});
