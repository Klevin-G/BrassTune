import { Check, ChevronDown, Copy, Link2, LogOut, Mail, Plus, Printer, RefreshCw, SlidersHorizontal, Trash2, UserPlus, Users, X } from 'lucide-react';
import { useEffect, useRef, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import {
  acceptEnsembleInvitation,
  addEnsembleMemberByUsername,
  createEnsembleGroup,
  declineEnsembleInvitation,
  friendlyUserFacingError,
  getEnsembleGroup,
  getEnsembleGroups,
  getEnsembleInvitations,
  getEnsembleReport,
  getEnsembleRoster,
  getEnsembleSummary,
  joinEnsembleByCode,
  leaveEnsembleGroup,
  removeEnsembleMember,
  rotateEnsembleJoinCode,
  type EnsembleInvitation,
  type EnsembleRosterStudent,
} from '../api/client';
import { NoteStatsTable } from '../components/NoteStatsTable';
import { PageHeader, ScreenContainer, SectionCard } from '../components/ui/AppPrimitives';
import { instrumentDisplayName } from '../domain/instrumentNames';
import { describeInTunePercent } from '../domain/tuningLanguage';
import { useAuth } from '../state/AuthContext';
import './EnsemblePage.css';

// Instruments a student can be tagged with. Kept in sync with the display-name catalog.
const INSTRUMENT_OPTIONS = ['trumpet', 'horn', 'trombone', 'euphonium', 'tuba'];
const isKnownInstrument = (id: string | null | undefined) => Boolean(id && INSTRUMENT_OPTIONS.includes(id.trim().toLowerCase()));

function relativeWhen(value: string | null): string {
  if (!value) return 'Never';
  const then = new Date(value).getTime();
  if (Number.isNaN(then)) return 'Never';
  const days = Math.floor((Date.now() - then) / 86_400_000);
  if (days <= 0) return 'Today';
  if (days === 1) return 'Yesterday';
  if (days < 7) return `${days}d ago`;
  if (days < 30) return `${Math.floor(days / 7)}w ago`;
  return `${Math.floor(days / 30)}mo ago`;
}

type Tone = 'green' | 'amber' | 'red' | 'muted';

// Plain-language read of an average absolute cents deviation (how far off, on average).
function describeAverageOff(absCents: number | null | undefined): { label: string; detail: string; tone: Tone } {
  if (absCents == null || Number.isNaN(absCents)) return { label: 'No plays yet', detail: '', tone: 'muted' };
  const rounded = Math.round(absCents);
  const detail = `${rounded}¢ off on average`;
  if (absCents <= 8) return { label: 'Spot on', detail, tone: 'green' };
  if (absCents <= 18) return { label: 'A little off', detail, tone: 'amber' };
  return { label: 'Off', detail, tone: 'red' };
}

function classCode(group: any): string | null {
  const existing = group?.join_code;
  return typeof existing === 'string' && existing.trim() ? existing.trim().toUpperCase() : null;
}

function invitationRoleLabel(role: string): string {
  if (role === 'assistant' || role === 'director') return 'Assistant — can view the active class roster';
  return 'Student';
}

const SAMPLE_ROSTER = [
  { name: 'Ava R.', instrument: 'trumpet', last: 'Today', minutes: 32 },
  { name: 'Marcus L.', instrument: 'trombone', last: 'Yesterday', minutes: 18 },
  { name: 'Priya S.', instrument: 'horn', last: '2d ago', minutes: 25 },
];

export function EnsemblePage() {
  const [summary, setSummary] = useState<any>(null);
  const [report, setReport] = useState<any>(null);
  const [roster, setRoster] = useState<EnsembleRosterStudent[] | null>(null);
  const [invitations, setInvitations] = useState<EnsembleInvitation[]>([]);
  const [groups, setGroups] = useState<any[]>([]);
  const [selectedGroup, setSelectedGroup] = useState<any>(null);
  const [newGroupName, setNewGroupName] = useState('');
  const [memberUsername, setMemberUsername] = useState('');
  const [inviteInstrument, setInviteInstrument] = useState('');
  const [ensembleStatus, setEnsembleStatus] = useState('');
  const [showCreate, setShowCreate] = useState(false);
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [copied, setCopied] = useState('');
  const [acceptInstruments, setAcceptInstruments] = useState<Record<number, string>>({});
  const [pendingRemove, setPendingRemove] = useState<{ memberId: number; label: string } | null>(null);
  const [pendingLeave, setPendingLeave] = useState<{ groupId: number; label: string } | null>(null);
  const [joinCodeInput, setJoinCodeInput] = useState('');
  const [joinInstrument, setJoinInstrument] = useState('');
  const [showJoin, setShowJoin] = useState(false);
  const [joining, setJoining] = useState(false);
  const [rotatingCode, setRotatingCode] = useState(false);
  const [creatingGroup, setCreatingGroup] = useState(false);
  const [invitingMember, setInvitingMember] = useState(false);
  const [respondingInvitations, setRespondingInvitations] = useState<Record<number, 'accept' | 'decline'>>({});
  const [loading, setLoading] = useState(true);
  const joinInFlightRef = useRef(false);
  const createInFlightRef = useRef(false);
  const inviteInFlightRef = useRef(false);
  const invitationResponsesInFlightRef = useRef(new Set<number>());
  const classLoadGenerationRef = useRef(0);
  const mountedRef = useRef(true);
  const leaveDialogRef = useRef<HTMLDivElement | null>(null);
  const leaveCancelRef = useRef<HTMLButtonElement | null>(null);
  const leaveReturnFocusRef = useRef<HTMLElement | null>(null);
  const [searchParams, setSearchParams] = useSearchParams();
  const auth = useAuth();
  const myId = auth.profile?.id;

  const managesGroup = (group: any): boolean => {
    if (typeof group?.viewer_can_manage === 'boolean') return group.viewer_can_manage;
    if (auth.profile?.role === 'admin') return true;
    return group?.director_user_id != null && group.director_user_id === myId;
  };
  const managesSelected = managesGroup(selectedGroup);
  const selectedMembership = (selectedGroup?.members ?? []).find(
    (member: any) => member.is_current_user || member.user_id === myId,
  );
  const canLeaveSelected = typeof selectedGroup?.viewer_can_leave === 'boolean'
    ? selectedGroup.viewer_can_leave
    : Boolean(!managesSelected && selectedMembership?.status === 'active');
  const hasDirectorReport = Boolean(managesSelected && selectedGroup && report);

  const memberLabel = (member: any) => {
    if (member.is_current_user) return 'You';
    if (member.username) return `@${member.username}`;
    return member.display_name ?? 'Member';
  };

  const isCurrentClassLoad = (generation: number) => (
    mountedRef.current && classLoadGenerationRef.current === generation
  );

  const selectGroup = async (groupId: number, requestedGeneration?: number) => {
    const generation = requestedGeneration ?? ++classLoadGenerationRef.current;
    if (isCurrentClassLoad(generation)) setLoading(true);
    try {
      const group = await getEnsembleGroup(groupId);
      if (!isCurrentClassLoad(generation)) return;
      setSelectedGroup(group);
      setSummary(null);
      setReport(null);
      setRoster(null);
      if (managesGroup(group)) {
        const [summaryData, reportData, rosterData] = await Promise.all([
          getEnsembleSummary(groupId).catch(() => null),
          getEnsembleReport(groupId).catch(() => null),
          getEnsembleRoster(groupId).catch(() => null),
        ]);
        if (!isCurrentClassLoad(generation)) return;
        setSummary(summaryData);
        setReport(reportData);
        setRoster(rosterData?.students ?? null);
      }
    } catch (error) {
      if (isCurrentClassLoad(generation)) {
        setEnsembleStatus(friendlyUserFacingError(error, 'Could not load your class.'));
      }
    } finally {
      if (isCurrentClassLoad(generation)) setLoading(false);
    }
  };

  const loadEverything = async (preferredGroupId?: number) => {
    const generation = ++classLoadGenerationRef.current;
    if (isCurrentClassLoad(generation)) setLoading(true);
    try {
      const [groupsData, invitesData] = await Promise.all([
        getEnsembleGroups(),
        getEnsembleInvitations().catch(() => ({ invitations: [] })),
      ]);
      if (!isCurrentClassLoad(generation)) return;
      setGroups(groupsData);
      setInvitations(invitesData.invitations ?? []);
      const nextGroup = groupsData.find((group) => group.id === preferredGroupId)
        ?? groupsData.find((group) => group.id === selectedGroup?.id)
        ?? groupsData[0];
      if (nextGroup) {
        await selectGroup(nextGroup.id, generation);
      } else {
        setSelectedGroup(null);
        setSummary(null);
        setReport(null);
        setRoster(null);
      }
    } catch (error) {
      if (isCurrentClassLoad(generation)) {
        setEnsembleStatus(friendlyUserFacingError(error, 'Could not load your class.'));
      }
    } finally {
      if (isCurrentClassLoad(generation)) setLoading(false);
    }
  };

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      classLoadGenerationRef.current += 1;
    };
  }, []);

  useEffect(() => {
    if (!auth.isSignedIn) {
      classLoadGenerationRef.current += 1;
      setGroups([]);
      setSelectedGroup(null);
      setSummary(null);
      setReport(null);
      setRoster(null);
      setInvitations([]);
      setEnsembleStatus('');
      setLoading(false);
      return;
    }
    void loadEverything();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [auth.isSignedIn]);

  useEffect(() => {
    const sharedCode = searchParams.get('join')?.trim().toUpperCase();
    if (!sharedCode) return;
    setJoinCodeInput(sharedCode);
    setShowJoin(true);
    setShowCreate(false);
  }, [searchParams]);

  useEffect(() => {
    if (!pendingLeave) return undefined;
    leaveCancelRef.current?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        setPendingLeave(null);
        return;
      }
      if (event.key !== 'Tab' || !leaveDialogRef.current) return;
      const focusable = Array.from(
        leaveDialogRef.current.querySelectorAll<HTMLElement>(
          'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
        ),
      );
      if (focusable.length === 0) return;
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
    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('keydown', onKeyDown);
      const returnFocus = leaveReturnFocusRef.current;
      leaveReturnFocusRef.current = null;
      if (returnFocus?.isConnected) returnFocus.focus();
    };
  }, [pendingLeave]);
  const respondToInvitation = async (invitation: EnsembleInvitation, accept: boolean) => {
    if (invitationResponsesInFlightRef.current.has(invitation.member_id)) return;
    invitationResponsesInFlightRef.current.add(invitation.member_id);
    setRespondingInvitations((current) => ({
      ...current,
      [invitation.member_id]: accept ? 'accept' : 'decline',
    }));
    try {
      if (accept) {
        // The student's own instrument choice is set as part of accepting.
        const chosen = acceptInstruments[invitation.member_id];
        await acceptEnsembleInvitation(invitation.member_id, chosen && chosen !== invitation.instrument_id ? chosen : undefined);
      } else {
        await declineEnsembleInvitation(invitation.member_id);
      }
      await loadEverything(accept ? invitation.group_id : undefined);
      setEnsembleStatus(accept ? `You joined “${invitation.group_name}”.` : `You declined “${invitation.group_name}”.`);
    } catch (error) {
      setEnsembleStatus(friendlyUserFacingError(error, 'Could not update the invitation.'));
    } finally {
      invitationResponsesInFlightRef.current.delete(invitation.member_id);
      if (mountedRef.current) {
        setRespondingInvitations((current) => {
          const next = { ...current };
          delete next[invitation.member_id];
          return next;
        });
      }
    }
  };

  const joinByCode = async () => {
    if (joinInFlightRef.current) return;
    const code = joinCodeInput.trim().toUpperCase();
    if (code.length < 4) {
      setEnsembleStatus('Enter the class code your teacher gave you.');
      return;
    }
    joinInFlightRef.current = true;
    setJoining(true);
    setEnsembleStatus('Joining class…');
    try {
      const result = await joinEnsembleByCode(code, joinInstrument || undefined);
      setJoinCodeInput('');
      setJoinInstrument('');
      setShowJoin(false);
      await loadEverything(result.group_id);
      setEnsembleStatus(`You joined “${result.group_name}”.`);
      if (searchParams.has('join')) {
        const next = new URLSearchParams(searchParams);
        next.delete('join');
        setSearchParams(next, { replace: true });
      }
    } catch (error) {
      if (error instanceof Error && /conflicts with existing account or ensemble data/i.test(error.message)) {
        await loadEverything();
        setEnsembleStatus('You’re already in that class. Your class list is up to date.');
      } else {
        setEnsembleStatus(friendlyUserFacingError(error, 'That code didn’t work. Double-check it with your teacher.'));
      }
    } finally {
      joinInFlightRef.current = false;
      setJoining(false);
    }
  };

  const createGroup = async () => {
    if (createInFlightRef.current) return;
    const groupName = newGroupName.trim();
    if (!groupName) {
      setEnsembleStatus('Give your class a name first.');
      return;
    }
    createInFlightRef.current = true;
    setCreatingGroup(true);
    try {
      const group = await createEnsembleGroup(groupName);
      setNewGroupName('');
      setShowCreate(false);
      await auth.refreshProfile().catch(() => undefined);
      await loadEverything(group.id);
      setEnsembleStatus(`“${group.name}” is ready. Add students below.`);
    } catch (error) {
      setEnsembleStatus(friendlyUserFacingError(error, 'Could not create the class.'));
    } finally {
      createInFlightRef.current = false;
      if (mountedRef.current) setCreatingGroup(false);
    }
  };

  const addMember = async () => {
    if (inviteInFlightRef.current) return;
    if (!selectedGroup?.id) {
      setEnsembleStatus('Pick a class before adding a student.');
      return;
    }
    if (!memberUsername.trim()) {
      setEnsembleStatus('Enter the student’s username first.');
      return;
    }
    const groupId = selectedGroup.id;
    const username = memberUsername.trim();
    const instrumentId = inviteInstrument;
    inviteInFlightRef.current = true;
    setInvitingMember(true);
    try {
      // Pass the instrument the director chose — never the director's own tuner setting.
      // The instrument is optional: if the director leaves it unset the student picks
      // their own when they accept the invitation.
      await addEnsembleMemberByUsername(groupId, {
        username,
        instrument_id: instrumentId || undefined,
        role_in_group: 'student',
      });
      setMemberUsername('');
      setInviteInstrument('');
      await selectGroup(groupId);
      setEnsembleStatus('Invite sent — they’ll see it when they sign in.');
    } catch (error) {
      setEnsembleStatus(friendlyUserFacingError(error, 'Could not send the invite. Check the username is exact.'));
    } finally {
      inviteInFlightRef.current = false;
      if (mountedRef.current) setInvitingMember(false);
    }
  };

  const doRemove = async () => {
    if (!selectedGroup?.id || !pendingRemove) return;
    const { memberId, label } = pendingRemove;
    setPendingRemove(null);
    try {
      await removeEnsembleMember(selectedGroup.id, memberId);
      await selectGroup(selectedGroup.id);
      setEnsembleStatus(`${label} removed.`);
    } catch (error) {
      setEnsembleStatus(friendlyUserFacingError(error, 'Could not remove the student.'));
    }
  };

  const doLeave = async () => {
    if (!pendingLeave) return;
    const leaving = pendingLeave;
    setPendingLeave(null);
    try {
      await leaveEnsembleGroup(leaving.groupId);
      await loadEverything();
      setEnsembleStatus(`You left “${leaving.label}”.`);
    } catch (error) {
      setEnsembleStatus(friendlyUserFacingError(error, 'Could not leave the class.'));
    }
  };

  const rotateJoinCode = async () => {
    if (!selectedGroup?.id || !managesSelected || rotatingCode) return;
    setRotatingCode(true);
    try {
      const result = await rotateEnsembleJoinCode(selectedGroup.id);
      setSelectedGroup((current: any) => current?.id === result.group_id ? { ...current, join_code: result.join_code } : current);
      setGroups((current) => current.map((group) => group.id === result.group_id ? { ...group, join_code: result.join_code } : group));
      setCopied('');
      setEnsembleStatus('Class code rotated. The previous code no longer works.');
    } catch (error) {
      setEnsembleStatus(friendlyUserFacingError(error, 'Could not rotate the class code.'));
    } finally {
      setRotatingCode(false);
    }
  };
  const copyText = async (text: string, key: string) => {
    try {
      await navigator.clipboard?.writeText(text);
    } catch {
      /* clipboard may be unavailable; the code stays visible on screen */
    }
    setCopied(key);
    window.setTimeout(() => setCopied((current) => (current === key ? '' : current)), 1600);
  };

  const handlePrint = () => {
    document.body.classList.add('ec-printing');
    const cleanup = () => {
      document.body.classList.remove('ec-printing');
      window.removeEventListener('afterprint', cleanup);
    };
    window.addEventListener('afterprint', cleanup);
    window.print();
    window.setTimeout(cleanup, 1500);
  };

  // ---- Signed out ---------------------------------------------------------
  if (!auth.isSignedIn) {
    return (
      <ScreenContainer>
        <PageHeader title="Class" description="See who’s practicing and how they’re doing." />
        <SectionCard title="Sign in to see your class">
          <p className="muted-copy">Sign in so your class rosters stay private and sync across your devices.</p>
          {auth.configured ? (
            <Link to="/?next=/ensemble" className="primary-button ec-signin-btn">Sign in or create an account</Link>
          ) : (
            <p className="settings-status" role="status">Cloud sign-in isn’t set up in this local environment.</p>
          )}
          <div className="ec-preview" aria-hidden="true">
            <div className="ec-preview-head">
              <span className="ec-preview-tag">Preview</span>
              <span className="ec-preview-title">Period 3 Brass</span>
            </div>
            <div className="ec-roster">
              {SAMPLE_ROSTER.map((student) => (
                <div className="ec-student-card" key={student.name}>
                  <div className="ec-student-top">
                    <span className="ec-student-name">{student.name}</span>
                  </div>
                  <div className="ec-student-meta">
                    <span className="ec-meta"><em>Instrument</em>{instrumentDisplayName(student.instrument)}</span>
                    <span className="ec-meta"><em>Last practice</em>{student.last}</span>
                    <span className="ec-meta"><em>This week</em>{student.minutes} min</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </SectionCard>
      </ScreenContainer>
    );
  }

  // ---- Signed in ----------------------------------------------------------
  const code = selectedGroup ? classCode(selectedGroup) : null;
  const origin = typeof window !== 'undefined' ? window.location.origin : '';
  const shareLink = code ? `${origin}/ensemble?join=${encodeURIComponent(code)}` : null;

  const renderStudentCard = (student: EnsembleRosterStudent) => {
    const invited = student.status === 'invited';
    const name = student.display_name ?? (student.username ? `@${student.username}` : 'Student');
    const onPitch = describeInTunePercent(student.in_tune_percentage);
    const tuning = describeAverageOff(student.average_abs_cents);
    return (
      <div className={`ec-student-card${invited ? ' ec-invited' : ''}`} key={student.member_id}>
        <div className="ec-student-top">
          <span className="ec-student-name">{name}</span>
          {invited && <span className="ec-badge ec-tone-amber">Invited</span>}
          <button
            className="ec-remove ec-no-print"
            type="button"
            onClick={() => setPendingRemove({ memberId: student.member_id, label: name })}
          >
            <Trash2 size={15} />
            <span>Remove</span>
          </button>
        </div>
        {invited ? (
          <p className="ec-invited-note">Waiting for them to accept your invite.</p>
        ) : (
          <>
            <div className="ec-student-meta">
              <span className="ec-meta"><em>Instrument</em>{instrumentDisplayName(student.instrument_id)}</span>
              <span className="ec-meta"><em>Last practice</em>{relativeWhen(student.last_practice_at)}</span>
              <span className="ec-meta"><em>Practice time</em>{student.practice_minutes} min</span>
            </div>
            {showAdvanced && (
              <div className="ec-advanced">
                <span className={`ec-stat ec-tone-${onPitch.tone}`}>
                  <em>On pitch</em>
                  <strong>{student.in_tune_percentage != null ? `${Math.round(student.in_tune_percentage)}%` : '—'}</strong>
                </span>
                <span className={`ec-stat ec-tone-${tuning.tone}`}>
                  <em>Tuning</em>
                  <strong>{tuning.label}</strong>
                  {tuning.detail && <small>{tuning.detail}</small>}
                </span>
                <span className="ec-stat ec-tone-muted">
                  <em>Sessions</em>
                  <strong>{student.sessions_count}</strong>
                </span>
              </div>
            )}
          </>
        )}
      </div>
    );
  };

  return (
    <ScreenContainer>
      <PageHeader
        title="Class"
        description="See who’s practicing and how they’re doing."
        action={hasDirectorReport ? (
          <button className="ghost-button ec-no-print" onClick={handlePrint} type="button">
            <Printer size={18} />
            Print report
          </button>
        ) : undefined}
      />

      {invitations.length > 0 && (
        <SectionCard title="You’re invited">
          <div className="ec-invite-cards">
            {invitations.map((invitation) => {
              const chosen = acceptInstruments[invitation.member_id] ?? (isKnownInstrument(invitation.instrument_id) ? invitation.instrument_id : '');
              const pendingAction = respondingInvitations[invitation.member_id];
              return (
                <div className="ec-invite-card" key={invitation.member_id}>
                  <span className="ec-invite-icon"><Mail size={18} /></span>
                  <div className="ec-invite-copy">
                    <strong>{invitation.group_name}</strong>
                    <em>{invitation.director_name ? `Invited by ${invitation.director_name}` : 'You were invited to join'}</em>
                    <span className="ec-invite-role">Role: {invitationRoleLabel(invitation.role_in_group)}</span>
                  </div>
                  <label className="ec-select ec-accept-select">
                    <span>Your instrument</span>
                    <select
                      value={chosen}
                      onChange={(event) => setAcceptInstruments((prev) => ({ ...prev, [invitation.member_id]: event.target.value }))}
                      disabled={Boolean(pendingAction)}
                    >
                      <option value="">Pick your instrument</option>
                      {INSTRUMENT_OPTIONS.map((id) => (
                        <option value={id} key={id}>{instrumentDisplayName(id)}</option>
                      ))}
                    </select>
                  </label>
                  <div className="ec-invite-actions">
                    <button className="primary-button" type="button" onClick={() => respondToInvitation(invitation, true)} disabled={Boolean(pendingAction)}>
                      <Check size={16} />
                      {pendingAction === 'accept' ? 'Joining…' : 'Accept'}
                    </button>
                    <button className="ghost-button" type="button" onClick={() => respondToInvitation(invitation, false)} disabled={Boolean(pendingAction)}>
                      <X size={16} />
                      {pendingAction === 'decline' ? 'Declining…' : 'Decline'}
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        </SectionCard>
      )}

      {ensembleStatus && <p className="settings-status" role="status" aria-live="polite">{ensembleStatus}</p>}

      {groups.length === 0 ? (
        <>
          <SectionCard title="Join your class" eyebrow="For students">
            <div className="ec-empty">
              <span className="ec-empty-icon"><Users size={26} /></span>
              <p className="muted-copy">Enter the class code your teacher gave you.</p>
              <div className="ec-create-row ec-no-print">
                <input
                  className="ec-input ec-code-input"
                  value={joinCodeInput}
                  onChange={(event) => setJoinCodeInput(event.target.value.toUpperCase())}
                  placeholder="e.g. BXK4QD"
                  aria-label="Class code"
                  autoCapitalize="characters"
                  maxLength={16}
                  disabled={joining}
                  onKeyDown={(event) => { if (event.key === 'Enter') joinByCode(); }}
                />
                <select className="ec-input" value={joinInstrument} onChange={(event) => setJoinInstrument(event.target.value)} aria-label="Your instrument" disabled={joining}>
                  <option value="">Your instrument</option>
                  {INSTRUMENT_OPTIONS.map((id) => (
                    <option key={id} value={id}>{instrumentDisplayName(id)}</option>
                  ))}
                </select>
                <button className="primary-button" type="button" onClick={joinByCode} disabled={joinCodeInput.trim().length < 4 || joining}>
                  <UserPlus size={18} />
                  {joining ? 'Joining…' : 'Join'}
                </button>
              </div>
              {auth.profile?.username && (
                <p className="ec-username-hint">
                  No code? Ask your teacher to add you by your username: <strong>@{auth.profile.username}</strong>
                </p>
              )}
            </div>
          </SectionCard>
          <SectionCard title="Start a class" eyebrow="For teachers">
            <div className="ec-empty">
              <p className="muted-copy">Name your class, then share the code so students can join.</p>
              <div className="ec-create-row ec-no-print">
                <input
                  className="ec-input"
                  value={newGroupName}
                  onChange={(event) => setNewGroupName(event.target.value)}
                  placeholder="e.g. Period 3 Brass"
                  aria-label="Class name"
                  disabled={creatingGroup}
                  onKeyDown={(event) => { if (event.key === 'Enter') createGroup(); }}
                />
                <button className="primary-button" type="button" onClick={createGroup} disabled={!newGroupName.trim() || creatingGroup}>
                  <Plus size={18} />
                  {creatingGroup ? 'Creating…' : 'Create a class'}
                </button>
              </div>
            </div>
          </SectionCard>
        </>
      ) : (
        <>
          <div className="ec-classbar ec-no-print">
            {groups.length > 1 ? (
              <div className="ec-class-tabs" aria-busy={loading}>
                {groups.map((group) => (
                  <button
                    key={group.id}
                    type="button"
                    className={`chip-tab ${selectedGroup?.id === group.id ? 'active' : ''}`}
                    onClick={() => selectGroup(group.id)}
                  >
                    {group.name}
                  </button>
                ))}
              </div>
            ) : <span />}
            <button className="ghost-button ec-newclass-btn" type="button" onClick={() => { setShowJoin((value) => !value); setShowCreate(false); }} aria-expanded={showJoin}>
              <UserPlus size={16} />
              Join another class
            </button>
            <button className="ghost-button" type="button" onClick={() => { setShowCreate((value) => !value); setShowJoin(false); }} aria-expanded={showCreate}>
              <Plus size={16} />
              New class
            </button>
          </div>

          {showJoin && (
            <SectionCard title="Join another class" className="ec-no-print">
              <div className="ec-create-row">
                <input
                  className="ec-input ec-code-input"
                  value={joinCodeInput}
                  onChange={(event) => setJoinCodeInput(event.target.value.toUpperCase())}
                  placeholder="Class code"
                  aria-label="Class code"
                  autoCapitalize="characters"
                  maxLength={16}
                  disabled={joining}
                  onKeyDown={(event) => { if (event.key === 'Enter') joinByCode(); }}
                />
                <select className="ec-input" value={joinInstrument} onChange={(event) => setJoinInstrument(event.target.value)} aria-label="Your instrument" disabled={joining}>
                  <option value="">Your instrument</option>
                  {INSTRUMENT_OPTIONS.map((id) => (
                    <option key={id} value={id}>{instrumentDisplayName(id)}</option>
                  ))}
                </select>
                <button className="primary-button" type="button" onClick={joinByCode} disabled={joinCodeInput.trim().length < 4 || joining}>
                  <UserPlus size={18} />
                  {joining ? 'Joining…' : 'Join'}
                </button>
              </div>
            </SectionCard>
          )}

          {showCreate && (
            <SectionCard className="ec-no-print">
              <div className="ec-create-row">
                <input
                  className="ec-input"
                  value={newGroupName}
                  onChange={(event) => setNewGroupName(event.target.value)}
                  placeholder="e.g. Jazz Band, Period 5"
                  aria-label="New class name"
                  disabled={creatingGroup}
                  onKeyDown={(event) => { if (event.key === 'Enter') createGroup(); }}
                />
                <button className="primary-button" type="button" onClick={createGroup} disabled={!newGroupName.trim() || creatingGroup}>
                  <Plus size={18} />
                  {creatingGroup ? 'Creating…' : 'Create a class'}
                </button>
              </div>
            </SectionCard>
          )}

          {!selectedGroup ? (
            <SectionCard title="Loading class">
              <p className="muted-copy" role="status">Loading your selected class…</p>
            </SectionCard>
          ) : managesSelected ? (
            <div className="ec-print-area">
              <SectionCard title={selectedGroup?.name ?? 'Class'}>
                <div className="ec-print-only ec-print-head">
                  <h2>{selectedGroup?.name ?? 'Class'}</h2>
                  <p>Class report · {new Date().toLocaleDateString()}</p>
                </div>

                <div className="ec-join ec-no-print">
                  <div className="ec-join-main">
                    <span className="ec-join-label">Class code</span>
                    <span className={`ec-join-code${code ? '' : ' unavailable'}`}>{code ?? 'Unavailable'}</span>
                    <span className="ec-join-help">
                      {code ? 'Students enter this code to join.' : 'Create a new code before sharing this class.'}
                    </span>
                  </div>
                  <div className="ec-join-actions">
                    <button className="ghost-button" type="button" onClick={() => code && copyText(code, 'code')} disabled={!code}>
                      <Copy size={15} />
                      {copied === 'code' ? 'Copied' : 'Copy code'}
                    </button>
                    <button className="ghost-button" type="button" onClick={() => shareLink && copyText(shareLink, 'link')} disabled={!shareLink}>
                      <Link2 size={15} />
                      {copied === 'link' ? 'Copied' : 'Share link'}
                    </button>
                    <button className="ghost-button" type="button" onClick={rotateJoinCode} disabled={rotatingCode}>
                      <RefreshCw size={15} />
                      {rotatingCode ? 'Rotating…' : code ? 'Rotate code' : 'Create code'}
                    </button>
                  </div>
                </div>

                <div className="ec-invite-row ec-no-print">
                  <label className="ec-select">
                    <span>Instrument</span>
                    <select value={inviteInstrument} onChange={(event) => setInviteInstrument(event.target.value)} disabled={invitingMember}>
                      <option value="">Choose (optional)</option>
                      {INSTRUMENT_OPTIONS.map((id) => (
                        <option value={id} key={id}>{instrumentDisplayName(id)}</option>
                      ))}
                    </select>
                  </label>
                  <label className="ec-field">
                    <span>Add a student by username</span>
                    <input
                      className="ec-input"
                      value={memberUsername}
                      onChange={(event) => setMemberUsername(event.target.value.toLowerCase())}
                      placeholder="student-username"
                      disabled={invitingMember}
                      onKeyDown={(event) => { if (event.key === 'Enter') addMember(); }}
                    />
                  </label>
                  <button className="primary-button ec-send-invite" type="button" onClick={addMember} disabled={!memberUsername.trim() || invitingMember}>
                    <UserPlus size={17} />
                    {invitingMember ? 'Sending…' : 'Send invite'}
                  </button>
                </div>

                {roster && roster.length > 0 ? (
                  <>
                    <div className="ec-roster-head">
                      <span className="ec-roster-count">{roster.length} {roster.length === 1 ? 'student' : 'students'}</span>
                      <button
                        className={`ec-advanced-toggle ec-no-print ${showAdvanced ? 'open' : ''}`}
                        type="button"
                        onClick={() => setShowAdvanced((value) => !value)}
                        aria-pressed={showAdvanced}
                      >
                        <SlidersHorizontal size={14} />
                        Advanced
                        <ChevronDown size={14} className="ec-caret" />
                      </button>
                    </div>
                    <div className="ec-roster">
                      {roster.map(renderStudentCard)}
                    </div>
                    {showAdvanced && (
                      <p className="ec-cents-note">“Cents” measure how sharp or flat a note is — closer to 0 is more in tune.</p>
                    )}
                  </>
                ) : (
                  <p className="muted-copy">No students yet. Add your first student above — stats appear once they join and practice.</p>
                )}
              </SectionCard>

              {hasDirectorReport && (
                <>
                  <SectionCard title="How each section is doing">
                    <div className="ec-sections">
                      {(summary?.sections ?? []).map((section: any) => {
                        const tuning = describeAverageOff(section.average_abs_cents);
                        return (
                          <article className="ec-section" key={section.instrument_id}>
                            <span className="ec-section-name">{instrumentDisplayName(section.instrument_id)}</span>
                            <strong className={`ec-tone-${tuning.tone}`}>{tuning.label}</strong>
                            <p>{section.session_count} sessions · {section.practice_minutes} min</p>
                          </article>
                        );
                      })}
                      {(summary?.sections ?? []).length === 0 && (
                        <p className="muted-copy">Section trends appear once your students log practice.</p>
                      )}
                    </div>
                  </SectionCard>

                  {report?.recommended_rehearsal_focus && (
                    <SectionCard title="What to work on next">
                      <p>{report.recommended_rehearsal_focus}</p>
                      <div className="ec-focus-steps">
                        {(report.suggested_long_tone_sequence ?? []).map((item: string, index: number) => (
                          <article key={item}>
                            <span>{index + 1}</span>
                            <p>{item}</p>
                          </article>
                        ))}
                      </div>
                    </SectionCard>
                  )}

                  {(report?.top_problem_notes ?? []).length > 0 && (
                    <SectionCard title="Notes to focus on">
                      <NoteStatsTable rows={report.top_problem_notes ?? []} />
                    </SectionCard>
                  )}
                </>
              )}
            </div>
          ) : (
            <SectionCard
              title={selectedGroup?.name ?? 'Class'}
              action={canLeaveSelected ? (
                <button
                  className="ghost-button ec-leave-class ec-no-print"
                  type="button"
                  onClick={(event) => {
                    leaveReturnFocusRef.current = event.currentTarget;
                    setPendingLeave({ groupId: selectedGroup.id, label: selectedGroup.name });
                  }}
                >
                  <LogOut size={15} />
                  Leave class
                </button>
              ) : undefined}
            >
              <div className="ec-roster">
                {(selectedGroup?.members ?? []).map((member: any) => (
                  <div className="ec-student-card" key={member.id}>
                    <div className="ec-student-top">
                      <span className="ec-student-name">{memberLabel(member)}</span>
                      {member.status === 'invited' && <span className="ec-badge ec-tone-amber">Invited</span>}
                    </div>
                    <div className="ec-student-meta">
                      <span className="ec-meta"><em>Instrument</em>{instrumentDisplayName(member.instrument_id)}</span>
                    </div>
                  </div>
                ))}
                {(selectedGroup?.members ?? []).length === 0 && <p className="muted-copy">No one else is in this class yet.</p>}
              </div>
            </SectionCard>
          )}
        </>
      )}

      {pendingRemove && (
        <div className="ec-modal-overlay ec-no-print" role="presentation" onClick={() => setPendingRemove(null)}>
          <div className="ec-modal" role="dialog" aria-modal="true" aria-labelledby="ec-remove-title" onClick={(event) => event.stopPropagation()}>
            <h3 id="ec-remove-title">Remove {pendingRemove.label}?</h3>
            <p className="muted-copy">They’ll come off this class roster. Their own practice history stays on their account.</p>
            <div className="ec-modal-actions">
              <button className="ghost-button" type="button" onClick={() => setPendingRemove(null)}>Cancel</button>
              <button className="ec-danger-btn" type="button" onClick={doRemove}>Remove</button>
            </div>
          </div>
        </div>
      )}

      {pendingLeave && (
        <div className="ec-modal-overlay ec-no-print" role="presentation" onClick={() => setPendingLeave(null)}>
          <div
            className="ec-modal"
            role="dialog"
            aria-modal="true"
            aria-labelledby="ec-leave-title"
            ref={leaveDialogRef}
            onClick={(event) => event.stopPropagation()}
          >
            <h3 id="ec-leave-title">Leave {pendingLeave.label}?</h3>
            <p className="muted-copy">You’ll lose access to this class. Your practice history stays on your account.</p>
            <div className="ec-modal-actions">
              <button className="ghost-button" type="button" ref={leaveCancelRef} onClick={() => setPendingLeave(null)}>Cancel</button>
              <button className="ec-danger-btn" type="button" onClick={doLeave}>Leave class</button>
            </div>
          </div>
        </div>
      )}
    </ScreenContainer>
  );
}
