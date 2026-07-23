import { Mic, MoreHorizontal, Music2, Play, Trash2 } from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState, type KeyboardEvent as ReactKeyboardEvent } from 'react';
import { Link } from 'react-router-dom';
import { listSessions } from '../api/client';
import { ExportButtons } from '../components/ExportButtons';
import { SessionAudioPlayer } from '../components/SessionAudioPlayer';
import { EmptyActionState, LoadingSkeleton, PageHeader, ScreenContainer, SectionCard, SelectionChip, StatusBadge } from '../components/ui/AppPrimitives';
import { instrumentDisplayName } from '../domain/instrumentNames';
import { describeInTunePercent } from '../domain/tuningLanguage';
import { deleteGuestSession, GUEST_WORKSPACE_ACCESS, listGuestSessions, type GuestSessionDetail } from '../domain/guestSessions';
import type { PracticeSession } from '../domain/types';
import { useAuth } from '../state/AuthContext';
import './SessionsPage.css';

type SessionFilter = 'all' | 'audio';
type SessionsLoadState = 'loading' | 'ready' | 'error';

function formatWhen(dateText: string) {
  const date = new Date(dateText);
  const day = date.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
  const time = date.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  return `${day} · ${time}`;
}

export function resolveDeleteDialogReturnTarget(trigger: HTMLElement) {
  return trigger.closest('details')?.querySelector<HTMLElement>('summary') ?? null;
}

function isUsableFocusTarget(target: HTMLElement | null) {
  return Boolean(target?.isConnected && target.getAttribute('aria-hidden') !== 'true' && !target.closest('[hidden]'));
}

export function resolvePostDeleteFocusTarget(savedTarget: HTMLElement | null, root: Document = document) {
  if (isUsableFocusTarget(savedTarget)) return savedTarget;
  const nextSummary = Array.from(root.querySelectorAll<HTMLElement>('.ps-overflow > summary')).find(isUsableFocusTarget);
  if (nextSummary) return nextSummary;
  const primaryFallback = root.querySelector<HTMLElement>('[data-delete-focus-fallback]');
  if (isUsableFocusTarget(primaryFallback)) return primaryFallback;
  const heading = root.querySelector<HTMLElement>('.ps-screen h1');
  return isUsableFocusTarget(heading) ? heading : null;
}

export function SessionsPage() {
  const auth = useAuth();
  const guestAccess = !auth.loading && !auth.isSignedIn && auth.guestMode ? GUEST_WORKSPACE_ACCESS : undefined;
  const [sessions, setSessions] = useState<PracticeSession[]>([]);
  const [filter, setFilter] = useState<SessionFilter>('all');
  const [status, setStatus] = useState('');
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [pendingDelete, setPendingDelete] = useState<PracticeSession | null>(null);
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [loadState, setLoadState] = useState<SessionsLoadState>('loading');
  const [retryKey, setRetryKey] = useState(0);
  const dialogRef = useRef<HTMLDivElement | null>(null);
  const cancelButtonRef = useRef<HTMLButtonElement | null>(null);
  const deleteOpenerRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    let active = true;
    const guestSessions = listGuestSessions(guestAccess);
    setLoadState('loading');
    if (!auth.isSignedIn) {
      setSessions(guestSessions);
      setLoadState('ready');
      return () => {
        active = false;
      };
    }
    setSessions(guestSessions);
    listSessions()
      .then((cloudSessions) => {
        if (!active) return;
        setSessions([...guestSessions, ...cloudSessions].sort((a, b) => new Date(b.started_at).getTime() - new Date(a.started_at).getTime()));
        setLoadState('ready');
      })
      .catch(() => {
        if (!active) return;
        setSessions(guestSessions);
        setLoadState('error');
      });
    return () => {
      active = false;
    };
  }, [auth.isSignedIn, auth.guestMode, auth.profile?.id, guestAccess, retryKey]);

  useEffect(() => {
    if (!pendingDelete) return;
    const frame = window.requestAnimationFrame(() => cancelButtonRef.current?.focus());
    return () => window.cancelAnimationFrame(frame);
  }, [pendingDelete]);

  const restoreDeleteFocus = useCallback(() => {
    window.requestAnimationFrame(() => {
      const target = resolvePostDeleteFocusTarget(deleteOpenerRef.current);
      if (!target) return;
      if (target.matches('h1') && !target.hasAttribute('tabindex')) target.setAttribute('tabindex', '-1');
      target.focus();
    });
  }, []);

  const dismissDeleteDialog = useCallback(() => {
    if (deleteBusy) return;
    setPendingDelete(null);
    restoreDeleteFocus();
  }, [deleteBusy, restoreDeleteFocus]);

  const confirmDelete = async () => {
    const session = pendingDelete;
    if (!session || !session.guest_session) {
      setPendingDelete(null);
      restoreDeleteFocus();
      return;
    }
    setDeleteBusy(true);
    try {
      const deleted = deleteGuestSession(session.id, guestAccess);
      if (!deleted) throw new Error('Guest workspace access is unavailable.');
      setSessions((current) => current.filter((item) => item.id !== session.id));
      setStatus('Recording deleted.');
      setPendingDelete(null);
      restoreDeleteFocus();
    } catch {
      setStatus('We could not delete that recording. Please try again.');
    } finally {
      setDeleteBusy(false);
    }
  };

  const handleDialogKeyDown = (event: ReactKeyboardEvent<HTMLDivElement>) => {
    if (event.key === 'Escape') {
      event.preventDefault();
      dismissDeleteDialog();
      return;
    }
    if (event.key !== 'Tab') return;
    const focusable = Array.from(
      dialogRef.current?.querySelectorAll<HTMLElement>('button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])') ?? [],
    );
    if (focusable.length === 0) {
      event.preventDefault();
      return;
    }
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
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
            <Link to="/practice" className="primary-button" data-delete-focus-fallback>
              <Mic size={18} />
              New recording
            </Link>
          ) : undefined
        }
      />

      {loadState === 'loading' && !hasSessions ? (
        <SectionCard title="Loading recordings" eyebrow="Sessions">
          <LoadingSkeleton rows={4} />
        </SectionCard>
      ) : loadState === 'error' && !hasSessions ? (
        <SectionCard title="Couldn’t load your recordings" eyebrow="Connection problem">
          <p className="ps-load-copy">Check your connection, then try again. Your recordings have not been removed.</p>
          <button className="primary-button" type="button" onClick={() => setRetryKey((current) => current + 1)}>
            Try again
          </button>
        </SectionCard>
      ) : !hasSessions ? (
        <EmptyActionState
          icon={Music2}
          title="No recordings yet"
          body="Record your first practice session and it will appear here."
          action={
            <Link to="/practice" className="primary-button" data-delete-focus-fallback>
              <Mic size={18} />
              Start practicing
            </Link>
          }
        />
      ) : (
        <SectionCard title="Your recordings" eyebrow={`${sessions.length} ${sessions.length === 1 ? 'recording' : 'recordings'}`}>
          {status && <p className="settings-status" aria-live="polite">{status}</p>}
          {loadState === 'loading' && (
            <p className="ps-load-status" role="status" aria-live="polite">Loading cloud recordings…</p>
          )}
          {loadState === 'error' && (
            <div className="ps-load-warning" role="status" aria-live="polite">
              <p>Cloud recordings could not load. Recordings saved on this device are still shown.</p>
              <button className="ghost-button" type="button" onClick={() => setRetryKey((current) => current + 1)}>Try again</button>
            </div>
          )}
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
                            <ExportButtons
                              sessionId={session.id}
                              guestSession={isGuest ? (session as GuestSessionDetail) : null}
                              audioAvailable={Boolean(session.audio_available)}
                            />
                            {isGuest && (
                              <button
                                type="button"
                                className="ps-overflow-delete"
                                onClick={(event) => {
                                  const details = event.currentTarget.closest('details');
                                  deleteOpenerRef.current = resolveDeleteDialogReturnTarget(event.currentTarget);
                                  details?.removeAttribute('open');
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
        <div className="ps-dialog-backdrop" role="presentation" onClick={dismissDeleteDialog}>
          <div
            ref={dialogRef}
            className="ps-dialog"
            role="dialog"
            aria-modal="true"
            aria-labelledby="ps-delete-title"
            aria-describedby="ps-delete-description"
            aria-busy={deleteBusy}
            onClick={(event) => event.stopPropagation()}
            onKeyDown={handleDialogKeyDown}
          >
            <h2 id="ps-delete-title">Delete this recording?</h2>
            <p id="ps-delete-description">This can&apos;t be undone.</p>
            <div className="ps-dialog-actions">
              <button ref={cancelButtonRef} className="ghost-button" type="button" onClick={dismissDeleteDialog} disabled={deleteBusy}>
                Keep it
              </button>
              <button className="ps-dialog-delete" type="button" onClick={confirmDelete} disabled={deleteBusy}>
                {deleteBusy ? 'Deleting…' : 'Delete'}
              </button>
            </div>
          </div>
        </div>
      )}
    </ScreenContainer>
  );
}
