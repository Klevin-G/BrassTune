import { Target } from 'lucide-react';
import type { Recommendation } from '../domain/types';
import { useI18n } from '../i18n/LocaleContext';

/**
 * Guest recommendations are persisted with a session so they remain useful
 * offline. Their first version used English strings, however, so localize the
 * presentation at the edge rather than showing an old stored sentence in a
 * newly selected language.
 */
export function RecommendationCard({
  recommendation,
  localizeGuestRecommendation = false,
}: {
  recommendation: Recommendation;
  localizeGuestRecommendation?: boolean;
}) {
  const { t } = useI18n();
  const title = localizeGuestRecommendation
    ? t('progress.needsMostWork', { note: recommendation.related_note })
    : recommendation.title;
  const category = localizeGuestRecommendation ? t('progress.recommended') : recommendation.category;
  const message = localizeGuestRecommendation ? t('progress.aimGreenBody') : recommendation.message;
  const exercises = localizeGuestRecommendation
    ? [
      t('warmup.long-tone.instruction'),
      t('packs.daily.drone.instruction'),
      t('progress.aimGreenBody'),
    ]
    : recommendation.suggested_exercises;

  return (
    <section className="recommendation-card">
      <div className="rec-heading">
        <Target size={18} />
        <div>
          <h3>{title}</h3>
          <span>{category}</span>
        </div>
      </div>
      <p>{message}</p>
      <ul>
        {exercises.slice(0, 3).map((item) => (
          <li key={item}>{item}</li>
        ))}
      </ul>
    </section>
  );
}
