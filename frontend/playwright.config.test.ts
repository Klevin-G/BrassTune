import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

import { CI_E2E_GLOBAL_TIMEOUT_MS } from './playwright.config';

describe('Playwright CI budget', () => {
  it('keeps the complete single-worker matrix inside the workflow step budget', () => {
    const workflow = readFileSync('../.github/workflows/frontend.yml', 'utf8');
    const browserStep = workflow.match(
      /- name: Browser release journeys\s+timeout-minutes:\s+(\d+)/,
    );

    expect(browserStep).not.toBeNull();
    const workflowTimeoutMs = Number(browserStep![1]) * 60_000;
    expect(CI_E2E_GLOBAL_TIMEOUT_MS).toBe(30 * 60_000);
    expect(workflowTimeoutMs).toBeGreaterThan(CI_E2E_GLOBAL_TIMEOUT_MS);
  });
});
