import { describe, expect, it } from 'vitest';
import practicePageSource from '../pages/PracticePage.tsx?raw';
import audioLabSource from '../pages/AudioLabPage.tsx?raw';
import localImportSource from '../components/LocalMediaImportPanel.tsx?raw';

describe('saved-session accounting call-site audit', () => {
  it('routes every production recorder and media-import success through the canonical owner-scoped method', () => {
    expect(practicePageSource).toContain('recordSavedSession(summary)');
    expect(audioLabSource).toContain('recordSavedSession(summary)');
    expect(localImportSource).toContain('recordSavedSession(stopped)');

    expect(practicePageSource).not.toContain('recordPracticeActivity(ownerId');
    expect(practicePageSource).not.toContain('recordActivity(minutes)');
  });

  it('accounts local imports only after guest or cloud saving has produced a stopped session', () => {
    const saveCall = localImportSource.indexOf('recordSavedSession(stopped)');
    expect(saveCall).toBeGreaterThan(localImportSource.indexOf('stopped = await stopSession(session.id)'));
    expect(saveCall).toBeGreaterThan(localImportSource.indexOf('stopped = saveGuestSessionFromFrames(draft, validFrames)'));
    expect(saveCall).toBeLessThan(localImportSource.indexOf('onImported?.(stopped)'));
    expect(localImportSource.slice(localImportSource.indexOf('catch (error)'), localImportSource.indexOf('finally {')))
      .not.toContain('recordSavedSession');
  });
});
