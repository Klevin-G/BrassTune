import { CalendarClock, Gauge, Music2, Percent, Sparkles, Target } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { getHeatmap, getProgress, getRecommendations, listSessions } from '../api/client';
import { HeatMapGrid } from '../components/HeatMapGrid';
import { RecommendationCard } from '../components/RecommendationCard';
import { EmptyActionState, MetricTile, PageHeader, ScreenContainer, SectionCard, StatusBadge } from '../components/ui/AppPrimitives';
import { buildGuestHeatmap, buildGuestNoteStats, buildGuestProgress, buildGuestRecommendations } from '../domain/guestInsights';
import { listGuestSessions } from '../domain/guestSessions';
import type { NoteStats, PracticeSession, ProgressMetrics, Recommendation } from '../domain/types';
import { useAppSettings } from '../state/AppSettingsContext';
import { useAuth } from '../state/AuthContext';

function minutes(seconds: number | undefined) {
  return Math.round((seconds ?? 0) / 60);
}

function topMeasuredNote(rows: NoteStats[]) {
  return [...rows]
    .filter((row) => row.has_data !== false)
    .sort((a, b) => b.problem_severity - a.problem_severity)[0];
}

export function DashboardPage() {
  const { instrumentId } = useAppSettings();
  const auth = useAuth();
  const [progress, setProgress] = useState<ProgressMetrics | null>(null);
  const [sessions, setSessions] = useState<PracticeSession[]>([]);
  const [heatmap, setHeatmap] = useState<NoteStats[]>([]);
  const [recommendations, setRecommendations] = useState<Recommendation[]>([]);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!auth.isSignedIn) {
      const guestSessions = listGuestSessions();
      const guestStats = buildGuestNoteStats(instrumentId);
      setProgress(guestSessions.length ? buildGuestProgress(instrumentId, guestStats) : null);
      setSessions(guestSessions.slice(0, 3));
      setHeatmap(buildGuestHeatmap(instrumentId, guestStats));
      setRecommendations(buildGuestRecommendations(guestStats).slice(0, 3));
      setError(null);
      return;
    }
    Promise.all([getProgress(instrumentId), listSessions(), getHeatmap(instrumentId), getRecommendations(instrumentId)])
      .then(([progressData, sessionData, heatmapData, recommendationData]) => {
        setProgress(progressData);
        setSessions(sessionData.slice(0, 3));
        setHeatmap(heatmapData);
        setRecommendations(recommendationData.slice(0, 3));
        setError(null);
      })
      .catch(() => setError('Practice mode is still available. Analytics will refresh when the service reconnects.'));
  }, [auth.isSignedIn, instrumentId]);

  const latestPoint = progress?.timeseries[progress.timeseries.length - 1];
  const focusNote = useMemo(() => topMeasuredNote(heatmap), [heatmap]);
  const primaryRecommendation = recommendations[0];
  const focusLabel = primaryRecommendation?.related_note || focusNote?.note_label || 'Bb4';
  const focusBody =
    primaryRecommendation?.message ||
    (focusNote
      ? `${focusNote.note_label} is averaging ${focusNote.avg_abs_cents.toFixed(1)} cents of absolute error.`
      : 'Start a short demo recording to populate your first focus note.');

  return (
    <ScreenContainer>
      <PageHeader
        eyebrow="Home"
        title="Today's intonation focus"
        description="Open with the note pattern that needs attention, then jump straight into a short, measurable practice block."
        action={
          <Link to="/practice" className="primary-button">
            <Gauge size={18} />
            Start practice
          </Link>
        }
        meta={<StatusBadge tone="gold">{instrumentId}</StatusBadge>}
      />
      {error && <div className="alert" role="status" aria-live="polite">{error}</div>}
      <SectionCard className="today-focus-card">
        <div>
          <p className="eyebrow">Next best rep</p>
          <h2>{primaryRecommendation?.title ?? 'Center the note before expanding range'}</h2>
          <p>{focusBody}</p>
          <div className="button-row">
            <Link to="/coach" className="ghost-button">
              <Sparkles size={18} />
              Build plan
            </Link>
            <Link to="/analytics" className="ghost-button">
              <Target size={18} />
              Diagnose notes
            </Link>
          </div>
        </div>
        <div className="today-focus-note" aria-label={`Focus note ${focusLabel}`}>
          <strong>{focusLabel}</strong>
          <span>{focusNote ? `${Math.round(focusNote.avg_signed_cents)}c` : 'focus'}</span>
        </div>
      </SectionCard>
      <div className="stats-grid">
        <MetricTile label="Avg error" value={`${(latestPoint?.avg_abs_cents ?? 0).toFixed(1)}c`} detail="recent sessions" icon={Gauge} tone="gold" />
        <MetricTile label="In tune" value={`${Math.round(latestPoint?.in_tune_percentage ?? 0)}%`} detail="within +/-5 cents" icon={Percent} tone="green" />
        <MetricTile label="Practice" value={`${minutes(progress?.total_practice_time_seconds)} min`} detail={progress?.consistency.practice_days_label} icon={CalendarClock} />
        <MetricTile label="Sessions" value={`${progress?.session_count ?? 0}`} detail="saved reviews" icon={Music2} />
      </div>
      <div className="two-column-grid">
        <SectionCard title="Full-range heat map" eyebrow="Written notes" action={<Link to="/analytics">Open analytics</Link>}>
          <HeatMapGrid rows={heatmap} compact />
        </SectionCard>
        <SectionCard title="Recent takes" eyebrow="Session timeline" action={<Link to="/sessions">All sessions</Link>}>
          <div className="timeline-stack">
            {sessions.length === 0 && (
              <EmptyActionState title="No sessions yet" body="Record a demo or microphone take to create your first review card." icon={Music2} />
            )}
            {sessions.map((session) => (
              <Link to={`/sessions/${session.id}`} className="session-timeline-card" key={session.id}>
                <div className="timeline-heading">
                  <span className="insight-icon">
                    <Music2 size={18} />
                  </span>
                  <div>
                    <strong>{session.name}</strong>
                    <span>{new Date(session.started_at).toLocaleDateString()}</span>
                  </div>
                </div>
                <div className="mini-stat-list">
                  <div className="mini-stat-row">
                    <span>Avg abs</span>
                    <strong>{session.average_abs_cents.toFixed(1)}c</strong>
                  </div>
                  <div className="mini-stat-row">
                    <span>In tune</span>
                    <strong>{Math.round(session.in_tune_percentage)}%</strong>
                  </div>
                  <div className="mini-stat-row">
                    <span>Notes</span>
                    <strong>{session.notes_count}</strong>
                  </div>
                </div>
              </Link>
            ))}
          </div>
        </SectionCard>
      </div>
      {recommendations.length > 1 && (
        <SectionCard title="More coach recommendations" eyebrow="Today">
          <div className="recommendation-grid">
            {recommendations.slice(1, 4).map((recommendation) => (
              <RecommendationCard key={`${recommendation.related_note}-${recommendation.category}`} recommendation={recommendation} />
            ))}
          </div>
        </SectionCard>
      )}
    </ScreenContainer>
  );
}
