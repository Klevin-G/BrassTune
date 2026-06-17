import { CalendarClock, Gauge, Music2, Percent } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { getHeatmap, getProgress, getRecommendations, listSessions } from '../api/client';
import { HeatMapGrid } from '../components/HeatMapGrid';
import { RecommendationCard } from '../components/RecommendationCard';
import { StatCard } from '../components/StatCard';
import type { NoteStats, PracticeSession, ProgressMetrics, Recommendation } from '../domain/types';
import { useAppSettings } from '../state/AppSettingsContext';

export function DashboardPage() {
  const { instrumentId } = useAppSettings();
  const [progress, setProgress] = useState<ProgressMetrics | null>(null);
  const [sessions, setSessions] = useState<PracticeSession[]>([]);
  const [heatmap, setHeatmap] = useState<NoteStats[]>([]);
  const [recommendations, setRecommendations] = useState<Recommendation[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([getProgress(instrumentId), listSessions(), getHeatmap(instrumentId), getRecommendations(instrumentId)])
      .then(([progressData, sessionData, heatmapData, recommendationData]) => {
        setProgress(progressData);
        setSessions(sessionData.slice(0, 5));
        setHeatmap(heatmapData);
        setRecommendations(recommendationData.slice(0, 3));
      })
      .catch(() => setError('Backend unavailable. Start the FastAPI server or keep using the tuner in demo mode.'));
  }, [instrumentId]);

  const latestPoint = progress?.timeseries[progress.timeseries.length - 1];
  return (
    <div className="page-grid">
      <section className="hero-panel">
        <div>
          <h2>Long-term intonation patterns, not just a momentary tuner.</h2>
          <p>Track which written notes drift sharp, flat, or unstable over time.</p>
        </div>
        <Link to="/practice" className="primary-button">
          <Gauge size={18} />
          Start practice
        </Link>
      </section>
      {error && <div className="alert">{error}</div>}
      <div className="stats-grid">
        <StatCard label="Avg error" value={`${(latestPoint?.avg_abs_cents ?? 0).toFixed(1)}c`} detail="recent sessions" icon={Gauge} />
        <StatCard label="In-tune" value={`${Math.round(latestPoint?.in_tune_percentage ?? 0)}%`} detail="within +/-5 cents" icon={Percent} />
        <StatCard label="Practice" value={`${Math.round((progress?.total_practice_time_seconds ?? 0) / 60)} min`} detail={progress?.consistency.practice_days_label} icon={CalendarClock} />
        <StatCard label="Sessions" value={`${progress?.session_count ?? 0}`} detail="stored locally" icon={Music2} />
      </div>
      <section className="panel wide">
        <div className="section-heading">
          <h2>Intonation heat map</h2>
          <Link to="/analytics">View analytics</Link>
        </div>
        <HeatMapGrid rows={heatmap} compact />
      </section>
      <section className="panel">
        <div className="section-heading">
          <h2>Recent sessions</h2>
          <Link to="/sessions">All sessions</Link>
        </div>
        <div className="session-list">
          {sessions.map((session) => (
            <Link to={`/sessions/${session.id}`} className="session-row" key={session.id}>
              <span>{session.name}</span>
              <strong>{session.average_abs_cents.toFixed(1)}c</strong>
            </Link>
          ))}
        </div>
      </section>
      <section className="panel">
        <div className="section-heading">
          <h2>Top recommendations</h2>
          <Link to="/coach">Practice coach</Link>
        </div>
        <div className="recommendation-stack">
          {recommendations.map((recommendation) => (
            <RecommendationCard key={`${recommendation.related_note}-${recommendation.category}`} recommendation={recommendation} />
          ))}
        </div>
      </section>
    </div>
  );
}
