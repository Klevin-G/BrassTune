import { CalendarDays, Download, Gauge, Music2, Plus, Sparkles, Trash2 } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { listSessions } from '../api/client';
import { ExportButtons } from '../components/ExportButtons';
import { SessionAudioPlayer } from '../components/SessionAudioPlayer';
import { EmptyActionState, PageHeader, ScreenContainer, SectionCard, SelectionChip } from '../components/ui/AppPrimitives';
import { deleteGuestSession, listGuestSessions, type GuestSessionDetail } from '../domain/guestSessions';
import type { PracticeSession } from '../domain/types';
import { useAuth } from '../state/AuthContext';

type SessionFilter = 'all' | 'week' | 'audio' | 'best' | 'work';

function isThisWeek(dateText: string) {
  const date = new Date(dateText);
  const now = new Date();
  const start = new Date(now);
  start.setDate(now.getDate() - 7);
  return date >= start;
}

export function SessionsPage() {
  const auth = useAuth();
  const [sessions, setSessions] = useState<PracticeSession[]>([]);
  const [filter, setFilter] = useState<SessionFilter>('all');
  const [status, setStatus] = useState('');

  useEffect(() => {
    const guestSessions = listGuestSessions();
    if (!auth.isSignedIn) {
      setSessions(guestSessions);
      return;
    }
    listSessions()
      .then((cloudSessions) => setSessions([...guestSessions, ...cloudSessions].sort((a, b) => new Date(b.started_at).getTime() - new Date(a.started_at).getTime())))
      .catch(() => setSessions(guestSessions));
  }, [auth.isSignedIn]);

  const deleteGuest = (session: PracticeSession) => {
    if (!session.guest_session) return;
    if (!window.confirm('Delete this guest session and its local audio from this device?')) return;
    deleteGuestSession(session.id);
    setSessions((current) => current.filter((item) => item.id !== session.id));
    setStatus('Guest session deleted from this device.');
  };

  const filtered = useMemo(() => {
    if (filter === 'week') return sessions.filter((session) => isThisWeek(session.started_at));
    if (filter === 'audio') return sessions.filter((session) => session.audio_available);
    if (filter === 'best') return sessions.filter((session) => session.in_tune_percentage >= 75);
    if (filter === 'work') return sessions.filter((session) => session.average_abs_cents >= 12 || session.in_tune_percentage < 55);
    return sessions;
  }, [filter, sessions]);

  return (
    <ScreenContainer>
      <PageHeader
        eyebrow="Sessions"
        title="Practice timeline"
        description="Review saved takes as evidence cards. Guest sessions stay on this device; sign in to sync sessions across devices and ensembles."
        action={
          <Link to="/practice" className="primary-button">
            <Plus size={18} />
            New session
          </Link>
        }
      />
      <SectionCard title="Saved takes" eyebrow={`${filtered.length} visible`}>
        {status && <p className="settings-status" aria-live="polite">{status}</p>}
        <div className="chip-row">
          <SelectionChip active={filter === 'all'} onClick={() => setFilter('all')}>All</SelectionChip>
          <SelectionChip active={filter === 'week'} onClick={() => setFilter('week')}>This week</SelectionChip>
          <SelectionChip active={filter === 'audio'} onClick={() => setFilter('audio')} tone="green">With audio</SelectionChip>
          <SelectionChip active={filter === 'best'} onClick={() => setFilter('best')} tone="green">Best</SelectionChip>
          <SelectionChip active={filter === 'work'} onClick={() => setFilter('work')} tone="red">Needs work</SelectionChip>
        </div>
        {filtered.length === 0 && (
          <EmptyActionState title="No matching sessions" body="Try another filter or record a short practice take." icon={Music2} />
        )}
        <div className="session-card-grid">
          {filtered.map((session) => (
            <article className="session-timeline-card" key={session.id}>
              <div className="timeline-heading">
                <span className="insight-icon">
                  <Music2 size={18} />
                </span>
                <div>
                  <strong>{session.name}</strong>
                  <span>{new Date(session.started_at).toLocaleString()}</span>
                </div>
              </div>
              <div className="mini-stat-list">
                <div className="mini-stat-row">
                  <span>Instrument</span>
                  <strong>{session.guest_session ? `${session.instrument_id} · guest` : session.instrument_id}</strong>
                </div>
                <div className="mini-stat-row">
                  <span>Notes</span>
                  <strong>{session.notes_count}</strong>
                </div>
                <div className="mini-stat-row">
                  <span>Avg abs</span>
                  <strong>{session.average_abs_cents.toFixed(1)}c</strong>
                </div>
              </div>
              <div className="timeline-row">
                <span>
                  <Gauge size={16} /> {Math.round(session.in_tune_percentage)}% in tune
                </span>
                <em>
                  <CalendarDays size={15} /> {Math.round(session.duration_seconds)}s
                </em>
              </div>
              <div className="timeline-row">
                <span>
                  <Sparkles size={16} /> Review analytics
                </span>
                <Link to={`/sessions/${session.id}`}>Open</Link>
              </div>
              <SessionAudioPlayer session={session} compact />
              <div className="session-card-actions">
                <Link to={`/sessions/${session.id}`} className="ghost-button">
                  <Sparkles size={16} />
                  Review
                </Link>
                <details className="export-menu">
                  <summary>
                    <Download size={16} />
                    Export
                  </summary>
                  <ExportButtons sessionId={session.id} guestSession={session.guest_session ? session as GuestSessionDetail : null} />
                </details>
                {session.guest_session && (
                  <button className="ghost-button danger-action" type="button" onClick={() => deleteGuest(session)}>
                    <Trash2 size={16} />
                    Delete
                  </button>
                )}
              </div>
            </article>
          ))}
        </div>
      </SectionCard>
    </ScreenContainer>
  );
}
