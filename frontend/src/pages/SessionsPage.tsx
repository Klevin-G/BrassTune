import { Mic, MoreHorizontal, Music2, Play, Trash2 } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { listSessions } from '../api/client';
import { ExportButtons } from '../components/ExportButtons';
import { SessionAudioPlayer } from '../components/SessionAudioPlayer';
import { EmptyActionState, PageHeader, ScreenContainer, SectionCard, SelectionChip, StatusBadge } from '../components/ui/AppPrimitives';
import { instrumentDisplayName } from '../domain/instrumentNames';
import { describeInTunePercent } from '../domain/tuningLanguage';
import { deleteGuestSession, listGuestSessions, type GuestSessionDetail } from '../domain/guestSessions';
import type { PracticeSession } from '../domain/types';
import { useAuth } from '../state/AuthContext';
import './SessionsPage.css';

type SessionFilter = 'all' | 'audio';

function formatWhen(dateText: string) {
  const date = new Date(dateText);
  const day = date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
  const time = date.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  return `${day} · ${time}`;
}

export function SessionsPage() {
  const auth = useAuth();
  const [sessions, setSessions] = useState<PracticeSession[]>([]);
  const [filter, setFilter] = useState<SessionFilter>('all');
  const [status, setStatus] = useState('');
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [pendingDelete, setPendingDelete] = useState<PracticeSession | null>(null);

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

  const confirmDelete = () => {
    const session = pendingDelete;
    if (!session || !session.guest_session) {
      setPendingDelete(null);
      return;
    }
    deleteGuestSession(session.id);
    setSessions((current) => current.filter((item) => item.id !== session.id));
    setStatus('Recording deleted.');
    setPendingDelete(null);
  };

  const filtered = useMemo(() => {
    if (filter === 'audio') return sessions.filter((session) => session.audio_available);
    return sessions;
  }, [filter, sessions]);

  const hasSessions = sessions.length > 0;

  return (
    <ScreenContainer className="ps-screen">
      <PageHeader
        eyebrow="Sessions"
        title="Your recordings"
        description="Every practice recording you make shows up here so you can listen back and see how in-tune you were."
        action={
          hasSessions ? (
            <Link to="/practice" className="primary-button">
              <Mic size={18} />
              New recording
            </Link>
          ) : undefined
        }
      />

      {!hasSessions ? (
        <EmptyActionState
          icon={Music2}
          title="No recordings yet"
          body="Record your first practice session and it will appear here."
          action={
            <Link to="/practice" className="primary-button">
              <Mic size={18} />
              Start practicing
            </Link>
          }
        />
      ) : (
        <SectionCard title="Your recordings" eyebrow={`${sessions.length} ${sessions.length === 1 ? 'recording' : 'recordings'}`}>
          {status && <p className="settings-status" aria-live="polite">{status}</p>}
          <div className="ps-filter-row">
            <SelectionChip active={filter === 'all'} onClick={() => setFilter('all')}>All</SelectionChip>
            <SelectionChip active={filter === 'audio'} onClick={() => setFilter('audio')} tone="green">With audio</SelectionChip>
          </div>

          {filtered.length === 0 ? (
            <EmptyActionState
              icon={Play}
              title="No recordings with audio yet"
              body="Recordings you save with sound will show up here."
              action={
                <button className="ghost-button" type="button" onClick={() => setFilter('all')}>
                  Show all recordings
                </button>
              }
            />
          ) : (
            <ul className="ps-list">
              {filtered.map((session) => {
                const verdict = describeInTunePercent(session.in_tune_percentage);
                const isGuest = Boolean(session.guest_session);
                const expanded = expandedId === session.id;
                return (
                  <li className="ps-item" key={session.id}>
                    <div className="ps-item-row">
                      <Link to={`/sessions/${session.id}`} className="ps-item-main">
                        <span className="ps-item-icon">
                          <Music2 size={18} />
                        </span>
                        <span className="ps-item-text">
                          <span className="ps-instrument">{instrumentDisplayName(session.instrument_id)}</span>
                          <span className="ps-date">
                            {formatWhen(session.started_at)}
                            {isGuest ? ' · Saved on this device' : ''}
                          </span>
                        </span>
                        <span className="ps-badge-slot">
                          <StatusBadge tone={verdict.tone}>{verdict.label}</StatusBadge>
                        </span>
                      </Link>

                      <div className="ps-item-actions">
                        {session.audio_available && (
                          <button
                            type="button"
                            className="ps-icon-btn"
                            aria-pressed={expanded}
                            aria-label={expanded ? 'Hide playback' : 'Listen back'}
                            onClick={() => setExpandedId(expanded ? null : session.id)}
                          >
                            <Play size={17} />
                          </button>
                        )}
                        <details className="ps-overflow">
                          <summary aria-label="More options">
                            <MoreHorizontal size={18} />
                          </summary>
                          <div className="ps-overflow-menu">
                            <p className="ps-overflow-label">Download · for teachers</p>
                            <ExportButtons sessionId={session.id} guestSession={isGuest ? (session as GuestSessionDetail) : null} />
                            {isGuest && (
                              <button
                                type="button"
                                className="ps-overflow-delete"
                                onClick={(event) => {
                                  event.currentTarget.closest('details')?.removeAttribute('open');
                                  setPendingDelete(session);
                                }}
                              >
                                <Trash2 size={16} />
                                Delete recording
                              </button>
                            )}
                          </div>
                        </details>
                      </div>
                    </div>

                    {expanded && session.audio_available && (
                      <div className="ps-item-audio">
                        <SessionAudioPlayer session={session} compact />
                      </div>
                    )}
                  </li>
                );
              })}
            </ul>
          )}
        </SectionCard>
      )}

      {pendingDelete && (
        <div className="ps-dialog-backdrop" role="presentation" onClick={() => setPendingDelete(null)}>
          <div
            className="ps-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="ps-delete-title"
            onClick={(event) => event.stopPropagation()}
          >
            <h2 id="ps-delete-title">Delete this recording?</h2>
            <p>This can&apos;t be undone.</p>
            <div className="ps-dialog-actions">
              <button className="ghost-button" type="button" onClick={() => setPendingDelete(null)}>
                Keep it
              </button>
              <button className="ps-dialog-delete" type="button" onClick={confirmDelete}>
                Delete
              </button>
            </div>
          </div>
        </div>
      )}
    </ScreenContainer>
  );
}
