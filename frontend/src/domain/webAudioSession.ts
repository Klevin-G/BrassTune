export type WebAudioSessionType = 'auto' | 'playback' | 'play-and-record';

type NavigatorWithAudioSession = Navigator & {
  audioSession?: {
    type: WebAudioSessionType;
  };
};

/**
 * Requests the web audio category that matches the active BrassTune task.
 *
 * Safari on iOS otherwise treats Web Audio as ambient sound, which is muted by
 * the Ring/Silent switch. Other browsers safely ignore this experimental API.
 */
export function setWebAudioSessionType(
  type: WebAudioSessionType,
  navigatorObject?: Navigator,
): boolean {
  const activeNavigator = navigatorObject
    ?? (typeof navigator === 'undefined' ? undefined : navigator);
  if (!activeNavigator) return false;
  const session = (activeNavigator as NavigatorWithAudioSession).audioSession;
  if (!session) return false;
  try {
    session.type = type;
    return session.type === type;
  } catch {
    return false;
  }
}
