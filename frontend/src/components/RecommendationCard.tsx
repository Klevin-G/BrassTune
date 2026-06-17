import { Target } from 'lucide-react';
import type { Recommendation } from '../domain/types';

export function RecommendationCard({ recommendation }: { recommendation: Recommendation }) {
  return (
    <section className="recommendation-card">
      <div className="rec-heading">
        <Target size={18} />
        <div>
          <h3>{recommendation.title}</h3>
          <span>{recommendation.category}</span>
        </div>
      </div>
      <p>{recommendation.message}</p>
      <ul>
        {recommendation.suggested_exercises.slice(0, 3).map((item) => (
          <li key={item}>{item}</li>
        ))}
      </ul>
    </section>
  );
}

