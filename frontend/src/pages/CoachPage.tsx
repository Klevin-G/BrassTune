import { useEffect, useState } from 'react';
import { getPracticePlan, getRecommendations } from '../api/client';
import { PracticePlanCard } from '../components/PracticePlanCard';
import { RecommendationCard } from '../components/RecommendationCard';
import type { PracticePlan, Recommendation } from '../domain/types';
import { useAppSettings } from '../state/AppSettingsContext';

export function CoachPage() {
  const { instrumentId } = useAppSettings();
  const [plan, setPlan] = useState<PracticePlan | null>(null);
  const [recommendations, setRecommendations] = useState<Recommendation[]>([]);
  useEffect(() => {
    Promise.all([getPracticePlan(instrumentId), getRecommendations(instrumentId)]).then(([planData, recommendationData]) => {
      setPlan(planData);
      setRecommendations(recommendationData);
    });
  }, [instrumentId]);
  return (
    <div className="page-grid">
      {plan && <PracticePlanCard plan={plan} />}
      <section className="panel wide">
        <h2>Rule-based recommendations</h2>
        <div className="recommendation-grid">
          {recommendations.map((recommendation) => (
            <RecommendationCard key={`${recommendation.related_note}-${recommendation.category}`} recommendation={recommendation} />
          ))}
        </div>
      </section>
    </div>
  );
}

