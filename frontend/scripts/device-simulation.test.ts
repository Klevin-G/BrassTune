import { describe, expect, it, vi } from 'vitest';
import {
  assertSimulationPortsAvailable,
  dismissOnboardingDialog,
  formatCheckoutIdentity,
  selectViewports,
  trackConditionalRoute,
  trackVerifiedRoute,
} from './device-simulation.mjs';

describe('device simulation route evidence', () => {
  it('records only steps whose navigation and assertions completed without a new issue', async () => {
    const routes: string[] = [];
    const issues: string[] = [];

    await trackVerifiedRoute(routes, 'Tuner', issues, async () => undefined);
    await trackVerifiedRoute(routes, 'Progress', issues, async () => { issues.push('overflow'); });
    await expect(trackVerifiedRoute(routes, 'Sessions', issues, async () => { throw new Error('navigation failed'); })).rejects.toThrow('navigation failed');

    expect(routes).toEqual(['Tuner']);
  });

  it('reports onboarding only for the viewport that actually runs and verifies it', async () => {
    const routes: string[] = [];
    const issues: string[] = [];
    const verify = vi.fn(async () => undefined);

    await trackConditionalRoute(false, routes, 'Onboarding', issues, verify);
    expect(verify).not.toHaveBeenCalled();
    expect(routes).toEqual([]);

    await trackConditionalRoute(true, routes, 'Onboarding', issues, verify);
    expect(verify).toHaveBeenCalledOnce();
    expect(routes).toEqual(['Onboarding']);
  });

  it('does not record conditional onboarding when verification adds an issue', async () => {
    const routes: string[] = [];
    const issues: string[] = [];

    await trackConditionalRoute(true, routes, 'Onboarding', issues, async () => {
      issues.push('dialog overflow');
    });

    expect(routes).toEqual([]);
  });

  it('dismisses onboarding through its current accessible close action', async () => {
    const click = vi.fn(async () => undefined);
    const waitFor = vi.fn(async () => undefined);
    const first = vi.fn(() => ({ click }));
    const dismiss = { count: vi.fn(async () => 2), first };
    const dialog = {
      getByRole: vi.fn((_role: string, options?: { name?: RegExp }) => (
        options?.name ? dismiss : { allTextContents: vi.fn(async () => []) }
      )),
      waitFor,
    };

    await dismissOnboardingDialog(dialog);

    expect(first).toHaveBeenCalledOnce();
    expect(click).toHaveBeenCalledOnce();
    expect(waitFor).toHaveBeenCalledWith({ state: 'hidden', timeout: 3000 });
  });

  it('fails immediately when an opened onboarding dialog has no known dismiss action', async () => {
    const dialog = {
      getByRole: vi.fn((_role: string, options?: { name?: RegExp }) => (
        options?.name
          ? { count: vi.fn(async () => 0) }
          : { allTextContents: vi.fn(async () => ['Back', 'Next']) }
      )),
      waitFor: vi.fn(),
    };

    await expect(dismissOnboardingDialog(dialog)).rejects.toThrow(
      'Onboarding opened without a supported dismiss action. Available buttons: Back, Next',
    );
    expect(dialog.waitFor).not.toHaveBeenCalled();
  });

  it('selects requested viewport slugs in request order and rejects typos', () => {
    const configured = [
      { slug: 'tiny-phone', width: 320 },
      { slug: 'ipad-portrait', width: 768 },
    ];

    expect(selectViewports(configured, 'ipad-portrait,tiny-phone')).toEqual([
      configured[1],
      configured[0],
    ]);
    expect(() => selectViewports(configured, 'iphone-modern')).toThrow(
      'Unknown device simulation viewport: iphone-modern',
    );
  });

  it('refuses unverified existing servers and reports the exact checkout identity', () => {
    expect(() => assertSimulationPortsAvailable({ apiReachable: true, appReachable: false })).toThrow(
      /refuses to reuse unverified servers.*8000/,
    );
    expect(() => assertSimulationPortsAvailable({ apiReachable: false, appReachable: true })).toThrow(
      /refuses to reuse unverified servers.*5173/,
    );
    expect(() => assertSimulationPortsAvailable({ apiReachable: false, appReachable: false })).not.toThrow();
    expect(formatCheckoutIdentity('abc123', true)).toBe('abc123 (dirty worktree)');
  });
});
