import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { LocaleProvider } from '../i18n/LocaleContext';
import { RecommendationCard } from './RecommendationCard';

const storedGuestRecommendation = {
  title: 'Bb4 tends sharp',
  message: 'This guest workspace stores an English sentence from an earlier visit.',
  severity: 'moderate issue',
  category: 'Sharp tendency',
  related_note: 'Bb4',
  suggested_exercises: ['Use an English stored exercise.'],
  suggested_focus: 'Mostly sharp',
  explanation: 'Stored locally.',
};

describe('RecommendationCard', () => {
  it('replaces persisted guest recommendation copy with locale-backed coaching at review time', () => {
    const markup = renderToStaticMarkup(createElement(
      LocaleProvider,
      null,
      createElement(RecommendationCard, {
        recommendation: storedGuestRecommendation,
        localizeGuestRecommendation: true,
      }),
    ));

    expect(markup).toContain('Bb4 needs the most work');
    expect(markup).toContain('Recommended');
    expect(markup).not.toContain(storedGuestRecommendation.message);
    expect(markup).not.toContain(storedGuestRecommendation.suggested_exercises[0]);
  });

  it('keeps server-provided recommendations unchanged', () => {
    const markup = renderToStaticMarkup(createElement(
      LocaleProvider,
      null,
      createElement(RecommendationCard, { recommendation: storedGuestRecommendation }),
    ));

    expect(markup).toContain(storedGuestRecommendation.message);
  });
});
