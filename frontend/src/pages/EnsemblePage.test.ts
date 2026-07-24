import { describe, expect, it, vi } from 'vitest';
import { classShareScope, copyClassShareText } from './EnsemblePage';

describe('class share clipboard behavior', () => {
  it('reports success only after the clipboard write resolves', async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    await expect(copyClassShareText({ writeText }, 'BRASS1')).resolves.toBe(true);
    expect(writeText).toHaveBeenCalledWith('BRASS1');
  });

  it('requires a manual fallback when clipboard access is missing or rejects', async () => {
    await expect(copyClassShareText(undefined, 'BRASS1')).resolves.toBe(false);
    await expect(copyClassShareText({ writeText: vi.fn().mockRejectedValue(new Error('denied')) }, 'BRASS1')).resolves.toBe(false);
  });

  it('scopes manual fallback text to the exact active class and join code', () => {
    expect(classShareScope({ id: 7, join_code: 'brass1' })).toBe('7:BRASS1');
    expect(classShareScope({ id: 8, join_code: 'brass1' })).toBe('8:BRASS1');
    expect(classShareScope({ id: 7, join_code: 'brass2' })).toBe('7:BRASS2');
    expect(classShareScope({ id: 7, join_code: '' })).toBeNull();
  });
});
