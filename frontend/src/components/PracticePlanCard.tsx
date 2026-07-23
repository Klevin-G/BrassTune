import type { PracticePlan } from '../domain/types';
import { StatusBadge } from './ui/AppPrimitives';
import { useI18n } from '../i18n/LocaleContext';

export function PracticePlanCard({ plan }: { plan: PracticePlan }) {
  const { t, formatNumber } = useI18n();
  const totalMinutes = plan.steps.reduce((sum, step) => sum + step.minutes, 0);

  return (
    <section className="practice-plan">
      <div className="practice-plan-hero">
        <div>
          <p className="eyebrow">{t('practicePlan.coach')}</p>
          <h2>{plan.title}</h2>
          <p>{plan.coach_message}</p>
        </div>
        <StatusBadge tone="gold"><bdi dir="ltr">{t('progress.minutesShort', { count: formatNumber(totalMinutes || 10) })}</bdi></StatusBadge>
      </div>
      <div className="focus-row">
        {plan.focus_notes.map((note) => (
          <strong key={note}><bdi dir="ltr">{note}</bdi></strong>
        ))}
      </div>
      <div className="plan-steps">
        {plan.steps.map((step) => (
          <article key={step.label}>
            <span><bdi dir="ltr">{t('progress.minutesShort', { count: formatNumber(step.minutes) })}</bdi></span>
            <h3>{step.label}</h3>
            <p>{step.detail}</p>
          </article>
        ))}
      </div>
    </section>
  );
}
