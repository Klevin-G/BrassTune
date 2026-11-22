import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { describe, expect, it } from 'vitest';

const bootstrap = readFileSync(new URL('../../public/theme-init.js', import.meta.url), 'utf8');

function initialTheme(stored: string | null, systemLight: boolean, storageDenied = false) {
  const dataset: Record<string, string> = {};
  runInNewContext(bootstrap, {
    localStorage: { getItem: () => { if (storageDenied) throw new Error('denied'); return stored; } },
    matchMedia: () => ({ matches: systemLight }),
    document: { documentElement: { dataset } },
  });
  return dataset;
}

describe('theme before React renders', () => {
  it('opens white on dark devices for fresh, invalid, or inaccessible preferences', () => {
    for (const preference of [null, 'invalid', 'brass-white']) {
      expect(initialTheme(preference, false)).toEqual({ themePreference: 'brass-white', theme: 'brass-white' });
    }
    expect(initialTheme(null, false, true).theme).toBe('brass-white');
  });

  it('honors explicit system, dark, and high-contrast preferences from first paint', () => {
    expect(initialTheme('system', true)).toEqual({ themePreference: 'system', theme: 'brass-white' });
    expect(initialTheme('system', false)).toEqual({ themePreference: 'system', theme: 'brass-night' });
    expect(initialTheme('brass-night', true).theme).toBe('brass-night');
    expect(initialTheme('high-contrast', true).theme).toBe('high-contrast');
  });
});
