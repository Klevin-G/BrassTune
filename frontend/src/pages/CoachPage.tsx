import { ArrowRight, Brain, Gauge, Target } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { getPracticePlan, getRecommendations } from '../api/client';
import { PracticePlanCard } from '../components/PracticePlanCard';
import { RecommendationCard } from '../components/RecommendationCard';
import { InsightCard, PageHeader, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
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
    <ScreenContainer>
      <PageHeader
        eyebrow="Coach"
        title="10-minute intonation plan"
        description="Turn analytics into a short drill sequence: calibrate, isolate the problem note, then transfer it into a musical pattern."
        action={
          <Link to="/practice" className="primary-button">
            Start plan
            <ArrowRight size={18} />
          </Link>
        }
      />
      {plan && <PracticePlanCard plan={plan} />}
      <div className="insight-grid">
        <InsightCard
          title="Why this helps"
          detail="Center, stabilize, transfer"
          body="The plan starts with an anchor note, narrows attention to one written-note tendency, then repeats it with changing airflow and valve/slide context."
          icon={Brain}
          tone="gold"
        />
        <InsightCard
          title="Success target"
          detail="Within +/-5 cents"
          body="Aim for consistent entrances and releases before chasing the smallest possible cents number."
          icon={Gauge}
          tone="green"
        />
        <InsightCard
          title="Focus scope"
          detail={plan?.focus_notes.join(', ') ?? instrumentId}
          body="A small note set is easier to compare across sessions than a full-range pass."
          icon={Target}
        />
      </div>
      <SectionCard title="Rule-based recommendations" eyebrow="Detailed drills">
        <div className="recommendation-grid">
          {recommendations.map((recommendation) => (
            <RecommendationCard key={`${recommendation.related_note}-${recommendation.category}`} recommendation={recommendation} />
          ))}
        </div>
      </SectionCard>
    </ScreenContainer>
  );
}
