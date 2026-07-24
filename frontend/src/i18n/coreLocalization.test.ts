import { describe, expect, it } from 'vitest';
import sessionsSource from '../pages/SessionsPage.tsx?raw';
import progressSource from '../pages/ProgressPage.tsx?raw';
import metronomeSource from '../pages/MetronomePage.tsx?raw';
import scoreSource from '../pages/ScorePracticePage.tsx?raw';
import adminSource from '../pages/AdminMetricsPage.tsx?raw';
import practiceSource from '../pages/PracticePage.tsx?raw';
import sessionReviewSource from '../pages/SessionReviewPage.tsx?raw';
import authGatewaySource from '../pages/AuthGatewayPage.tsx?raw';
import sessionAudioSource from '../components/SessionAudioPlayer.tsx?raw';
import dateRangeSource from '../components/DateRangeFilter.tsx?raw';
import exportSource from '../components/ExportButtons.tsx?raw';
import heatmapSource from '../components/HeatMapGrid.tsx?raw';
import localMediaSource from '../components/LocalMediaImportPanel.tsx?raw';
import noteStatsSource from '../components/NoteStatsTable.tsx?raw';
import practicePlanSource from '../components/PracticePlanCard.tsx?raw';
import progressChartSource from '../components/ProgressChart.tsx?raw';
import recommendationSource from '../components/RecommendationCard.tsx?raw';
import signalMeterSource from '../components/SignalMeter.tsx?raw';
import statCardSource from '../components/StatCard.tsx?raw';
import themeSelectorSource from '../components/ThemeSelector.tsx?raw';

const coreFiles = [
  ['SessionsPage.tsx', sessionsSource],
  ['ProgressPage.tsx', progressSource],
  ['MetronomePage.tsx', metronomeSource],
  ['ScorePracticePage.tsx', scoreSource],
  ['AdminMetricsPage.tsx', adminSource],
  ['PracticePage.tsx', practiceSource],
  ['SessionReviewPage.tsx', sessionReviewSource],
  ['AuthGatewayPage.tsx', authGatewaySource],
  ['SessionAudioPlayer.tsx', sessionAudioSource],
  ['DateRangeFilter.tsx', dateRangeSource],
  ['ExportButtons.tsx', exportSource],
  ['HeatMapGrid.tsx', heatmapSource],
  ['LocalMediaImportPanel.tsx', localMediaSource],
  ['NoteStatsTable.tsx', noteStatsSource],
  ['PracticePlanCard.tsx', practicePlanSource],
  ['ProgressChart.tsx', progressChartSource],
  ['RecommendationCard.tsx', recommendationSource],
  ['SignalMeter.tsx', signalMeterSource],
  ['StatCard.tsx', statCardSource],
  ['ThemeSelector.tsx', themeSelectorSource],
];

const visibleLiteralPatterns = [
  /aria-label=["'][A-Z][^"']*["']/g,
  /(?:title|description|eyebrow)=["'][A-Z][^"']*["']/g,
  /placeholder=["'][A-Z][^"']*["']/g,
  />\s*[A-Z][A-Za-z][^<{\n]*</g,
  /set(?:Status|Message|Error)\(["'][A-Z][^"']*["']/g,
];

const routedFiles = [
  ['SessionsPage.tsx', sessionsSource],
  ['ProgressPage.tsx', progressSource],
  ['MetronomePage.tsx', metronomeSource],
  ['ScorePracticePage.tsx', scoreSource],
  ['AdminMetricsPage.tsx', adminSource],
  ['PracticePage.tsx', practiceSource],
  ['SessionReviewPage.tsx', sessionReviewSource],
  ['AuthGatewayPage.tsx', authGatewaySource],
];

describe('core routed localization coverage', () => {
  it('keeps new user-facing literals behind message IDs', () => {
    const offenders: string[] = [];
    for (const [fileName, fileSource] of coreFiles) {
      const source = fileSource
        .replace(/>BPM</g, '>{BPM}<')
        .replace(/>BrassTune</g, '>{BRAND}<');
      for (const pattern of visibleLiteralPatterns) {
        for (const match of source.matchAll(pattern)) offenders.push(`${fileName}: ${match[0]}`);
      }
    }
    expect(offenders).toEqual([]);
  });

  it('initializes i18n on every primary routed surface in this audit', () => {
    for (const [fileName, fileSource] of routedFiles) {
      expect(fileSource, fileName).toContain('useI18n');
    }
  });

  it('renders persisted guest recommendations through locale-backed copy in session review', () => {
    expect(recommendationSource).toContain('useI18n');
    expect(sessionReviewSource).toContain('localizeGuestRecommendation={Boolean(session.guest_session)}');
    expect(sessionReviewSource).toContain("? t('sessionReview.review')");
  });
});
