import { describe, expect, it, vi } from 'vitest';
import { copyClassShareText } from './EnsemblePage';

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
});
