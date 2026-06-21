import { Gauge, Music2, Percent, Timer } from 'lucide-react';
import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { useParams } from 'react-router-dom';
import { getSession, getSessionAnalytics } from '../api/client';
import { ExportButtons } from '../components/ExportButtons';
import { HeatMapGrid } from '../components/HeatMapGrid';
import { NoteStatsTable } from '../components/NoteStatsTable';
import { RecommendationCard } from '../components/RecommendationCard';
import { SessionAudioPlayer } from '../components/SessionAudioPlayer';
import { LoadingSkeleton, MetricTile, PageHeader, ScreenContainer, SectionCard, StatusBadge } from '../components/ui/AppPrimitives';
import { getGuestSession, isGuestSessionId, type GuestSessionDetail } from '../domain/guestSessions';
import type { NoteEvent, NoteStats, PracticeSession, Recommendation } from '../domain/types';

type SessionDetail = PracticeSession & { samples_count: number; note_events: NoteEvent[] };

export function SessionReviewPage() {
  const { id } = useParams();
  const [session, setSession] = useState<SessionDetail | null>(null);
  const [stats, setStats] = useState<NoteStats[]>([]);
  const [heatmap, setHeatmap] = useState<NoteStats[]>([]);
  const [recommendations, setRecommendations] = useState<Recommendation[]>([]);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);

  useEffect(() => {
    if (!id) return;
    setLoading(true);
    setNotFound(false);
    if (isGuestSessionId(id)) {
      const guestSession = getGuestSession(id);
      if (guestSession) {
        setSession(guestSession);
        setStats(guestSession.note_stats);
        setHeatmap(guestSession.heatmap);
        setRecommendations(guestSession.recommendations);
        setLoading(false);
      } else {
        setNotFound(true);
        setLoading(false);
      }
      return;
    }
    Promise.all([getSession(id), getSessionAnalytics(id)])
      .then(([sessionData, analytics]) => {
        setSession(sessionData);
        setStats(analytics.note_stats);
        setHeatmap(analytics.heatmap);
        setRecommendations(analytics.recommendations);
        setLoading(false);
      })
      .catch(() => {
        const guestSession = getGuestSession(id);
        if (!guestSession) {
          setNotFound(true);
          setLoading(false);
          return;
        }
        setSession(guestSession);
        setStats(guestSession.note_stats);
        setHeatmap(guestSession.heatmap);
        setRecommendations(guestSession.recommendations);
        setLoading(false);
      });
  }, [id]);

  if (!session && loading) {
    return (
      <ScreenContainer>
        <SectionCard title="Loading session">
          <LoadingSkeleton rows={4} />
        </SectionCard>
      </ScreenContainer>
    );
  }

  if (!session || notFound) {
    return (
      <ScreenContainer>
        <SectionCard title="Session not found" eyebrow="Review">
          <p className="muted-copy">This session is not available on this device or account.</p>
          <div className="settings-actions">
            <Link className="primary-button" to="/practice">Record a take</Link>
            <Link className="ghost-button" to="/sessions">Open sessions</Link>
          </div>
        </SectionCard>
      </ScreenContainer>
    );
  }

  return (
    <ScreenContainer>
      <PageHeader
        eyebrow="Session review"
        title={session.name}
        description={
          session.guest_session
            ? `Guest session saved on this device ${new Date(session.started_at).toLocaleString()} with ${session.notes_count} detected note events.`
            : `Recorded ${new Date(session.started_at).toLocaleString()} with ${session.notes_count} detected note events.`
        }
        action={<ExportButtons sessionId={session.id} guestSession={session.guest_session ? session as GuestSessionDetail : null} />}
        meta={<StatusBadge tone="gold">{session.guest_session ? 'guest practice' : session.instrument_id}</StatusBadge>}
      />
      <div className="stats-grid">
        <MetricTile label="Avg abs" value={`${session.average_abs_cents.toFixed(1)}c`} icon={Gauge} tone="gold" />
        <MetricTile
          label="Avg signed"
          value={`${session.average_signed_cents > 0 ? '+' : ''}${session.average_signed_cents.toFixed(1)}c`}
          icon={Music2}
        />
        <MetricTile label="In tune" value={`${Math.round(session.in_tune_percentage)}%`} icon={Percent} tone="green" />
        <MetricTile label="Samples" value={`${session.samples_count}`} detail={`${Math.round(session.duration_seconds)}s`} icon={Timer} />
      </div>
      <SectionCard title="Relisten" eyebrow={session.audio_available ? 'Session audio' : 'Playback unavailable'}>
        <SessionAudioPlayer session={session} />
      </SectionCard>
      <div className="two-column-grid">
        <SectionCard title="Session heat map" eyebrow="Written notes">
          <HeatMapGrid rows={heatmap} />
        </SectionCard>
        <SectionCard title="Note timeline" eyebrow="First events">
          <div className="timeline-stack">
            {session.note_events.slice(0, 8).map((event) => (
              <div className="timeline-row" key={event.id}>
                <strong>{event.note_label}</strong>
                <span>{event.avg_signed_cents > 0 ? '+' : ''}{event.avg_signed_cents.toFixed(1)}c</span>
                <em>{event.duration_seconds.toFixed(1)}s</em>
              </div>
            ))}
          </div>
        </SectionCard>
      </div>
      <SectionCard title="Session recommendations" eyebrow="Takeaways">
        <div className="recommendation-grid">
          {recommendations.map((recommendation) => (
            <RecommendationCard key={`${recommendation.related_note}-${recommendation.category}`} recommendation={recommendation} />
          ))}
        </div>
      </SectionCard>
      <SectionCard title="Note performance" eyebrow="Detailed rows">
        <NoteStatsTable rows={stats} />
      </SectionCard>
    </ScreenContainer>
  );
}
