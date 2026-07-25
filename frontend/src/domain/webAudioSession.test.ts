import { describe, expect, it } from 'vitest';
import { setWebAudioSessionType } from './webAudioSession';

describe('web audio session category', () => {
  it('requests playback so iOS Web Audio is not tied to the Ring/Silent switch', () => {
    const navigatorLike = { audioSession: { type: 'auto' } } as unknown as Navigator;
    expect(setWebAudioSessionType('playback', navigatorLike)).toBe(true);
    expect((navigatorLike as Navigator & { audioSession: { type: string } }).audioSession.type).toBe('playback');
  });

  it('falls back safely when the browser does not expose AudioSession', () => {
    expect(setWebAudioSessionType('playback', {} as Navigator)).toBe(false);
  });
});
