import { describe, expect, it } from 'vitest';
import { shouldShowMicrophoneDemoFallback } from './PracticePage';

describe('Practice microphone fallback', () => {
  it('keeps Demo visible when the browser does not support microphone capture', () => {
    expect(shouldShowMicrophoneDemoFallback(
      false,
      false,
      'Microphone input is unavailable in this browser.',
      'unavailable',
    )).toBe(true);
  });

  it('does not show the fallback while Demo or a live microphone is active', () => {
    expect(shouldShowMicrophoneDemoFallback(true, false, 'Microphone input is unavailable.', 'unavailable')).toBe(false);
    expect(shouldShowMicrophoneDemoFallback(false, true, 'Listening.', 'running')).toBe(false);
  });
});
