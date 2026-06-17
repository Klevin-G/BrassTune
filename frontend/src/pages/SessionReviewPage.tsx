import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import { getSession, getSessionAnalytics } from '../api/client';
import { ExportButtons } from '../components/ExportButtons';
import { HeatMapGrid } from '../components/HeatMapGrid';
import { NoteStatsTable } from '../components/NoteStatsTable';
import { RecommendationCard } from '../components/RecommendationCard';
import { StatCard } from '../components/StatCard';
import type { NoteStats, PracticeSession, Recommendation } from '../domain/types';

export function SessionReviewPage() {
  const { id } = useParams();
  const [session, setSession] = useState<(PracticeSession & { samples_count: number }) | null>(null);
  const [stats, setStats] = useState<NoteStats[]>([]);
  const [heatmap, setHeatmap] = useState<NoteStats[]>([]);
  const [recommendations, setRecommendations] = useState<Recommendation[]>([]);

  useEffect(() => {
    if (!id) return;
    Promise.all([getSession(id), getSessionAnalytics(id)]).then(([sessionData, analytics]) => {
      setSession(sessionData);
      setStats(analytics.note_stats);
      setHeatmap(analytics.heatmap);
      setRecommendations(analytics.recommendations);
    });
  }, [id]);

  if (!session) return <div className="panel">Loading session...</div>;

  return (
    <div className="page-grid">
      <section className="panel wide">
        <div className="section-heading">
          <div>
            <h2>{session.name}</h2>
            <p>{new Date(session.started_at).toLocaleString()}</p>
          </div>
          <ExportButtons sessionId={session.id} />
        </div>
        <div className="stats-grid">
          <StatCard label="Avg abs" value={`${session.average_abs_cents.toFixed(1)}c`} />
          <StatCard label="Avg signed" value={`${session.average_signed_cents > 0 ? '+' : ''}${session.average_signed_cents.toFixed(1)}c`} />
          <StatCard label="In-tune" value={`${Math.round(session.in_tune_percentage)}%`} />
          <StatCard label="Samples" value={`${session.samples_count}`} />
        </div>
      </section>
      <section className="panel wide">
        <h2>Session heat map</h2>
        <HeatMapGrid rows={heatmap} />
      </section>
      <section className="panel wide">
        <h2>Note performance</h2>
        <NoteStatsTable rows={stats} />
      </section>
      <section className="panel wide">
        <h2>Session recommendations</h2>
        <div className="recommendation-grid">
          {recommendations.map((recommendation) => (
            <RecommendationCard key={`${recommendation.related_note}-${recommendation.category}`} recommendation={recommendation} />
          ))}
        </div>
      </section>
    </div>
  );
}

