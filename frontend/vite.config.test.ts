import { describe, expect, it } from 'vitest';
import { resolveBuildRevision } from './vite.config';

const explicitSha = 'A'.repeat(40);
const vercelSha = 'b'.repeat(40);
const githubSha = 'c'.repeat(40);

describe('resolveBuildRevision', () => {
  it('prefers the explicit build SHA and normalizes it', () => {
    expect(resolveBuildRevision({
      BRASSTUNE_FRONTEND_BUILD_SHA: ` ${explicitSha} `,
      VERCEL_GIT_COMMIT_SHA: vercelSha,
      GITHUB_SHA: githubSha,
    })).toBe(explicitSha.toLowerCase());
  });

  it('falls back from the Vercel Git SHA to the GitHub SHA', () => {
    expect(resolveBuildRevision({
      VERCEL_GIT_COMMIT_SHA: vercelSha,
      GITHUB_SHA: githubSha,
    })).toBe(vercelSha);
    expect(resolveBuildRevision({ GITHUB_SHA: githubSha })).toBe(githubSha);
  });

  it('uses an explicit unknown marker only when no revision source exists', () => {
    expect(resolveBuildRevision({})).toBe('unknown');
  });

  it('rejects non-immutable revision values', () => {
    expect(() => resolveBuildRevision({
      BRASSTUNE_FRONTEND_BUILD_SHA: 'main',
    })).toThrow(/full 40-character Git commit SHA/);
  });
});
