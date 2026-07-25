import { describe, expect, it, vi } from 'vitest';
import { retryAudioPlayback } from './SessionAudioPlayer';

describe('SessionAudioPlayer', () => {
  it('actually asks the media element to reload after a decode failure', () => {
    const load = vi.fn();
    expect(retryAudioPlayback({ load })).toBe(true);
    expect(load).toHaveBeenCalledOnce();
  });

  it('fails safely when the media element was removed before retry', () => {
    expect(retryAudioPlayback(null)).toBe(false);
  });
});
