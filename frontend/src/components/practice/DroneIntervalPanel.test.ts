import { describe, expect, it } from 'vitest';
import { droneRecentHref, droneSelectionFromSearch } from './DroneIntervalPanel';

describe('drone recent selection', () => {
  it('persists both the written note and interval in a recent route', () => {
    const selection = { note: 'F#', interval: 7 };
    const href = droneRecentHref(selection);

    expect(href).toBe('/practice?tool=drone&note=F%23&interval=7');
    expect(droneSelectionFromSearch(new URLSearchParams(href.split('?')[1]))).toEqual(selection);
  });

  it('restores valid navigated selections and safely falls back for malformed recents', () => {
    expect(droneSelectionFromSearch(new URLSearchParams('note=Eb&interval=4'))).toEqual({ note: 'Eb', interval: 4 });
    expect(droneSelectionFromSearch(new URLSearchParams('note=H&interval=99'))).toEqual({ note: 'Bb', interval: 0 });
  });
});
