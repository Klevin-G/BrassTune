import { Mic, MoreHorizontal, Music2, Play, Trash2 } from 'lucide-react';
import { useCallback, useEffect, useMemo, useRef, useState, type KeyboardEvent as ReactKeyboardEvent } from 'react';
import { Link } from 'react-router-dom';
import { deleteSessionAudio, friendlyUserFacingError, listSessions, type SessionAudioDeleteResponse } from '../api/client';
import { ExportButtons } from '../components/ExportButtons';
import { SessionAudioPlayer } from '../components/SessionAudioPlayer';
import { EmptyActionState, LoadingSkeleton, PageHeader, ScreenContainer, SectionCard, SelectionChip, StatusBadge } from '../components/ui/AppPrimitives';
import { describeInTunePercent } from '../domain/tuningLanguage';
import { deleteGuestSession, GUEST_WORKSPACE_ACCESS, listGuestSessions, type GuestSessionDetail } from '../domain/guestSessions';
import type { PracticeSession } from '../domain/types';
import { useAuth } from '../state/AuthContext';
import { usePracticeLibrary } from '../state/PracticeLibraryContext';
import { useI18n } from '../i18n/LocaleContext';
import type { MessageId } from '../i18n/messages.base';
import './SessionsPage.css';

type SessionFilter = 'all' | 'audio';
type SessionsLoadState = 'loading' | 'ready' | 'error';

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

export function sessionAfterAudioDeletion(session: PracticeSession): PracticeSession {
  return {
    ...session,
    audio_available: false,
    audio_mime_type: null,
    audio_duration_seconds: null,
    audio_size_bytes: null,
    audio_uploaded_at: null,
  };
}

export function deleteDialogMessageIds(isGuest: boolean): { title: MessageId; body: MessageId; cancel: MessageId } {
  return isGuest
    ? { title: 'sessions.deleteTitle', body: 'sessions.deleteBody', cancel: 'sessions.keep' }
    : { title: 'sessions.deleteAudioTitle', body: 'sessions.deleteAudioBody', cancel: 'sessions.keepAudio' };
}

export function sessionAudioDeletionStatusId(cleanupPending: boolean): MessageId {
  return cleanupPending ? 'sessions.audioDeletePending' : 'sessions.audioDeleted';
}

export type SessionDeletionResult =
  | { type: 'guest-session-deleted'; updatedSession: null }
  | { type: 'cloud-audio-deleted'; cleanupPending: boolean; updatedSession: PracticeSession }
  | { type: 'failed'; error: unknown; keepDialogOpen: true; alertRole: 'alert' };

export async function executeSessionDeletion(
  session: PracticeSession,
  operations: {
    deleteGuestSession: (sessionId: number) => boolean;
    deleteCloudAudio(sessionId: number): Promise<SessionAudioDeleteResponse>;
    detachReflections: (sessionId: string) => void;
  },
): Promise<SessionDeletionResult> {
  try {
    if (session.guest_session) {
      if (!operations.deleteGuestSession(session.id)) throw new Error();
      operations.detachReflections(String(session.id));
      return { type: 'guest-session-deleted', updatedSession: null };
    }
    const result = await operations.deleteCloudAudio(session.id);
    if (!result.deleted) throw new Error();
    return { type: 'cloud-audio-deleted', cleanupPending: result.cleanup_pending, updatedSession: sessionAfterAudioDeletion(session) };
  } catch (error) {
    return { type: 'failed', error, keepDialogOpen: true, alertRole: 'alert' };
  }
}

export function SessionsPage() {
  const { t, formatDate } = useI18n();
  const auth = useAuth();
  const { detachReflectionsForSession } = usePracticeLibrary();
  const guestAccess = !auth.loading && !auth.isSignedIn && auth.guestMode ? GUEST_WORKSPACE_ACCESS : undefined;
  const [sessions, setSessions] = useState<PracticeSession[]>([]);
  const [filter, setFilter] = useState<SessionFilter>('all');
  const [status, setStatus] = useState('');
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [pendingDelete, setPendingDelete] = useState<PracticeSession | null>(null);
  const [deleteBusy, setDeleteBusy] = useState(false);
  const [deleteError, setDeleteError] = useState('');
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
    setDeleteError('');
    setPendingDelete(null);
    restoreDeleteFocus();
  }, [deleteBusy, restoreDeleteFocus]);

  const confirmDelete = async () => {
    const session = pendingDelete;
    if (!session) {
      setPendingDelete(null);
      restoreDeleteFocus();
      return;
    }
    setDeleteBusy(true);
    setDeleteError('');
    const result = await executeSessionDeletion(session, {
      deleteGuestSession: (sessionId) => deleteGuestSession(sessionId, guestAccess),
      deleteCloudAudio: deleteSessionAudio,
      detachReflections: detachReflectionsForSession,
    });
    if (result.type === 'failed') {
      const message = session.guest_session ? t('sessions.deleteFailed') : friendlyUserFacingError(result.error);
      setDeleteError(message);
      setDeleteBusy(false);
      return;
    }
    try {
      if (result.type === 'guest-session-deleted') {
        setSessions((current) => current.filter((item) => item.id !== session.id));
        setStatus(t('sessions.deleted'));
      } else {
        setSessions((current) => current.map((item) => (item.id === session.id ? result.updatedSession : item)));
        if (expandedId === session.id) setExpandedId(null);
        setStatus(t(sessionAudioDeletionStatusId(result.cleanupPending)));
      }
      setPendingDelete(null);
      restoreDeleteFocus();
    } catch {
      setDeleteError(session.guest_session ? t('sessions.deleteFailed') : friendlyUserFacingError(undefined));
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
        eyebrow={t('sessions.eyebrow')}
        title={t('sessions.title')}
        description={t('sessions.description')}
        action={
          hasSessions ? (
            <Link to="/practice" className="primary-button" data-delete-focus-fallback>
              <Mic size={18} />
              {t('sessions.new')}
            </Link>
          ) : undefined
        }
      />

      {loadState === 'loading' && !hasSessions ? (
        <SectionCard title={t('sessions.loading')} eyebrow={t('sessions.eyebrow')}>
          <LoadingSkeleton rows={4} label={t('sessions.loading')} />
        </SectionCard>
      ) : loadState === 'error' && !hasSessions ? (
        <SectionCard title={t('sessions.loadFailed')} eyebrow={t('sessionReview.connection')}>
          <p className="ps-load-copy">{t('sessions.loadFailedBody')}</p>
          <button className="primary-button" type="button" onClick={() => setRetryKey((current) => current + 1)}>
            {t('auth.tryAgain')}
          </button>
        </SectionCard>
      ) : !hasSessions ? (
        <EmptyActionState
          icon={Music2}
          title={t('sessions.empty')}
          body={t('sessions.emptyBody')}
          action={
            <Link to="/practice" className="primary-button" data-delete-focus-fallback>
              <Mic size={18} />
              {t('auth.start')}
            </Link>
          }
        />
      ) : (
        <SectionCard title={t('sessions.title')} eyebrow={t('sessions.count', { count: sessions.length })}>
          {status && <p className="settings-status" aria-live="polite">{status}</p>}
          {loadState === 'loading' && (
            <p className="ps-load-status" role="status" aria-live="polite">{t('sessions.loadingCloud')}</p>
          )}
          {loadState === 'error' && (
            <div className="ps-load-warning" role="status" aria-live="polite">
              <p>{t('sessions.cloudFailed')}</p>
              <button className="ghost-button" type="button" onClick={() => setRetryKey((current) => current + 1)}>{t('auth.tryAgain')}</button>
            </div>
          )}
          <div className="ps-filter-row">
            <SelectionChip active={filter === 'all'} onClick={() => setFilter('all')}>{t('sessions.all')}</SelectionChip>
            <SelectionChip active={filter === 'audio'} onClick={() => setFilter('audio')} tone="green">{t('sessions.withAudio')}</SelectionChip>
          </div>

          {filtered.length === 0 ? (
            <EmptyActionState
              icon={Play}
              title={t('sessions.noAudio')}
              body={t('sessions.noAudioBody')}
              action={
                <button className="ghost-button" type="button" onClick={() => setFilter('all')}>
                  {t('sessions.showAll')}
                </button>
              }
            />
          ) : (
            <ul className="ps-list">
              {filtered.map((session) => {
                const verdict = describeInTunePercent(session.in_tune_percentage);
                const isGuest = Boolean(session.guest_session);
                const canDeleteCloudAudio = !isGuest && Boolean(session.audio_available);
                const expanded = expandedId === session.id;
                return (
                  <li className="ps-item" key={session.id}>
                    <div className="ps-item-row">
                      <Link to={`/sessions/${session.id}`} className="ps-item-main">
                        <span className="ps-item-icon">
                          <Music2 size={18} />
                        </span>
                        <span className="ps-item-text">
                          <span className="ps-instrument">{t(`instrument.${session.instrument_id}` as MessageId)}</span>
                          <span className="ps-date">
                            {formatDate(new Date(session.started_at), { dateStyle: 'medium', timeStyle: 'short' })}
                            {isGuest ? ` · ${t('sessionReview.savedDevice')}` : ''}
                          </span>
                        </span>
                        <span className="ps-badge-slot">
                          <StatusBadge tone={verdict.tone}>{t(verdict.tone === 'green' ? 'tuning.inTune' : verdict.tone === 'amber' ? 'playAlong.grade.close' : verdict.tone === 'red' ? 'playAlong.grade.off' : 'class.noPlays')}</StatusBadge>
                        </span>
                      </Link>

                      <div className="ps-item-actions">
                        {session.audio_available && (
                          <button
                            type="button"
                            className="ps-icon-btn"
                            aria-pressed={expanded}
                            aria-label={t(expanded ? 'sessions.hidePlayback' : 'sessionAudio.listenBack')}
                            onClick={() => setExpandedId(expanded ? null : session.id)}
                          >
                            <Play size={17} />
                          </button>
                        )}
                        <details className="ps-overflow">
                          <summary aria-label={t('sessions.moreOptions')}>
                            <MoreHorizontal size={18} />
                          </summary>
                          <div className="ps-overflow-menu">
                            <p className="ps-overflow-label">{t('sessions.downloadTeacher')}</p>
                            <ExportButtons
                              sessionId={session.id}
                              guestSession={isGuest ? (session as GuestSessionDetail) : null}
                              audioAvailable={Boolean(session.audio_available)}
                            />
                            {(isGuest || canDeleteCloudAudio) && (
                              <button
                                type="button"
                                className="ps-overflow-delete"
                                onClick={(event) => {
                                  const details = event.currentTarget.closest('details');
                                  deleteOpenerRef.current = resolveDeleteDialogReturnTarget(event.currentTarget);
                                  details?.removeAttribute('open');
                                  setDeleteError('');
                                  setPendingDelete(session);
                                }}
                              >
                                <Trash2 size={16} />
                                {t(isGuest ? 'sessions.deleteRecording' : 'sessions.deleteAudio')}
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
            <h2 id="ps-delete-title">{t(deleteDialogMessageIds(Boolean(pendingDelete.guest_session)).title)}</h2>
            <p id="ps-delete-description">{t(deleteDialogMessageIds(Boolean(pendingDelete.guest_session)).body)}</p>
            {deleteError && <p role="alert">{deleteError}</p>}
            <div className="ps-dialog-actions">
              <button ref={cancelButtonRef} className="ghost-button" type="button" onClick={dismissDeleteDialog} disabled={deleteBusy}>
                {t(deleteDialogMessageIds(Boolean(pendingDelete.guest_session)).cancel)}
              </button>
              <button className="ps-dialog-delete" type="button" onClick={confirmDelete} disabled={deleteBusy}>
                {t(deleteBusy ? 'sessions.deleting' : 'common.delete')}
              </button>
            </div>
          </div>
        </div>
      )}
    </ScreenContainer>
  );
}
