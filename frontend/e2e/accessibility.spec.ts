import AxeBuilder from '@axe-core/playwright';
import { expect, test } from 'playwright/test';

const routes = [
  '/',
  '/practice',
  '/auth/sign-in',
  '/settings',
  '/sessions/-12345',
  '/ensemble',
  '/privacy',
];

test.beforeEach(async ({ page }) => {
  await page.addInitScript(() => {
    localStorage.setItem('brasstune.onboardingComplete', 'true');
    localStorage.setItem('brasstune.demoMode', 'true');
    localStorage.setItem('brasstune.guestSessions.v1', JSON.stringify([
      {
        id: -12345,
        user_id: 0,
        instrument_id: 'trumpet',
        name: 'Guest accessibility take',
        started_at: '2026-06-20T00:00:00.000Z',
        ended_at: '2026-06-20T00:00:04.000Z',
        duration_seconds: 4,
        reference_pitch_hz: 440,
        notes_count: 1,
        average_signed_cents: 2,
        average_abs_cents: 4,
        in_tune_percentage: 80,
        audio_available: false,
        guest_session: true,
        created_at: '2026-06-20T00:00:00.000Z',
        samples_count: 1,
        note_events: [
          {
            id: -1,
            session_id: -12345,
            instrument_id: 'trumpet',
            written_note: 'G',
            written_octave: 4,
            note_label: 'G4',
            concert_note: 'F',
            concert_octave: 4,
            started_at_ms: 0,
            ended_at_ms: 4000,
            duration_ms: 4000,
            duration_seconds: 4,
            sample_count: 12,
            avg_signed_cents: 2,
            avg_abs_cents: 4,
            median_cents: 2,
            stddev_cents: 1,
            min_cents: -2,
            max_cents: 5,
            in_tune_percentage: 80,
            stability_score: 92,
            created_at: '2026-06-20T00:00:00.000Z',
          },
        ],
        note_stats: [
          {
            written_note: 'G',
            written_octave: 4,
            note_label: 'G4',
            avg_signed_cents: 2,
            avg_abs_cents: 4,
            median_cents: 2,
            stddev_cents: 1,
            in_tune_percentage: 80,
            duration_ms: 4000,
            duration_seconds: 4,
            sample_count: 12,
            event_count: 1,
            stability_score: 92,
            trend: 'guest_local',
            severity: 'green',
            problem_severity: 4,
            has_data: true,
            severity_color: 'green',
            recommendation_summary: 'G4 averaged 4 cents in guest practice.',
          },
        ],
        heatmap: [],
        recommendations: [],
        frames: [],
      },
    ]));
  });
});

for (const route of routes) {
  test(`serious accessibility smoke: ${route}`, async ({ page }) => {
    await page.goto(route);
    await expect(page.getByRole('main')).toBeVisible();
    const results = await new AxeBuilder({ page })
      .include('main')
      .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
      .analyze();
    const serious = results.violations.filter((violation) => violation.impact === 'serious' || violation.impact === 'critical');
    expect(serious, JSON.stringify(serious, null, 2)).toEqual([]);
  });
}
