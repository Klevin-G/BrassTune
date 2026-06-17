import type { PracticePlan } from '../domain/types';

export function PracticePlanCard({ plan }: { plan: PracticePlan }) {
  return (
    <section className="practice-plan">
      <h2>{plan.title}</h2>
      <p>{plan.coach_message}</p>
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

