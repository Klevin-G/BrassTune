import type { PracticePlan } from '../domain/types';
import { StatusBadge } from './ui/AppPrimitives';

export function PracticePlanCard({ plan }: { plan: PracticePlan }) {
  const totalMinutes = plan.steps.reduce((sum, step) => sum + step.minutes, 0);

  return (
    <section className="practice-plan">
      <div className="practice-plan-hero">
        <div>
          <p className="eyebrow">Coach plan</p>
          <h2>{plan.title}</h2>
          <p>{plan.coach_message}</p>
        </div>
        <StatusBadge tone="gold">{totalMinutes || 10} min</StatusBadge>
      </div>
      <div className="focus-row">
        {plan.focus_notes.map((note) => (
          <strong key={note}>{note}</strong>
        ))}
      </div>
      <div className="plan-steps">
        {plan.steps.map((step) => (
          <article key={step.label}>
            <span>{step.minutes} min</span>
            <h3>{step.label}</h3>
            <p>{step.detail}</p>
          </article>
        ))}
      </div>
    </section>
  );
}
