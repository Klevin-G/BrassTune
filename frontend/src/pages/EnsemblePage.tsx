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
import { describeInTunePercent } from '../domain/tuningLanguage';
import { useAuth } from '../state/AuthContext';
import { gatewayPathWithReturn } from '../domain/authNavigation';
import { useI18n } from '../i18n/LocaleContext';
import type { MessageId } from '../i18n/messages.base';
import './EnsemblePage.css';

// Instruments a student can be tagged with. Kept in sync with the display-name catalog.
const INSTRUMENT_OPTIONS = ['trumpet', 'horn', 'trombone', 'euphonium', 'tuba'];
const isKnownInstrument = (id: string | null | undefined) => Boolean(id && INSTRUMENT_OPTIONS.includes(id.trim().toLowerCase()));

function relativeWhen(value: string | null, t: ReturnType<typeof useI18n>['t'], formatNumber: ReturnType<typeof useI18n>['formatNumber']): string {
  if (!value) return t('class.never');
  const then = new Date(value).getTime();
  if (Number.isNaN(then)) return t('class.never');
  const days = Math.floor((Date.now() - then) / 86_400_000);
  if (days <= 0) return t('class.today');
  if (days === 1) return t('class.yesterday');
  if (days < 7) return t('class.daysAgo', { count: formatNumber(days) });
  if (days < 30) return t('class.weeksAgo', { count: formatNumber(Math.floor(days / 7)) });
  return t('class.monthsAgo', { count: formatNumber(Math.floor(days / 30)) });
}

type Tone = 'green' | 'amber' | 'red' | 'muted';
type ClassResourceState = 'idle' | 'ready' | 'error';

type ClassMutationToken = {
  accountKey: string;
  loadGeneration: number;
  mutationEpoch: number;
};

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

export function classShareScope(group: any): string | null {
  const code = classCode(group);
  return Number.isInteger(group?.id) && code ? `${group.id}:${code}` : null;
}

function invitationRoleLabel(role: string, t: ReturnType<typeof useI18n>['t']): string {
  if (role === 'assistant' || role === 'director') return t('class.roleAssistant');
  return t('class.student');
}

const SAMPLE_ROSTER = [
  { name: 'Ava R.', instrument: 'trumpet', last: 'Today', minutes: 32 },
  { name: 'Marcus L.', instrument: 'trombone', last: 'Yesterday', minutes: 18 },
  { name: 'Priya S.', instrument: 'horn', last: '2d ago', minutes: 25 },
];

export async function copyClassShareText(
  clipboard: Pick<Clipboard, 'writeText'> | null | undefined,
  text: string,
): Promise<boolean> {
  if (!clipboard || typeof clipboard.writeText !== 'function') return false;
  try {
    await clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}

export function EnsemblePage() {
  const { locale, t, formatDate, formatNumber } = useI18n();
  const localizedError = (error: unknown, id: MessageId) => locale === 'en' ? friendlyUserFacingError(error, t(id)) : t(id);
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
  const [manualCopy, setManualCopy] = useState<{ scope: string; key: string; text: string } | null>(null);
  const [summaryState, setSummaryState] = useState<ClassResourceState>('idle');
  const [reportState, setReportState] = useState<ClassResourceState>('idle');
  const [rosterState, setRosterState] = useState<ClassResourceState>('idle');
  const [invitationsState, setInvitationsState] = useState<ClassResourceState>('idle');
  const [acceptInstruments, setAcceptInstruments] = useState<Record<number, string>>({});
  const [pendingRemove, setPendingRemove] = useState<{ memberId: number; label: string } | null>(null);
  const [pendingLeave, setPendingLeave] = useState<{ groupId: number; label: string } | null>(null);
  const [joinCodeInput, setJoinCodeInput] = useState('');
  const [joinInstrument, setJoinInstrument] = useState('');
  const [showJoin, setShowJoin] = useState(false);
  const [joining, setJoining] = useState(false);
  const [leavingGroup, setLeavingGroup] = useState(false);
  const [removingMember, setRemovingMember] = useState(false);
  const [rotatingCode, setRotatingCode] = useState(false);
  const [creatingGroup, setCreatingGroup] = useState(false);
  const [invitingMember, setInvitingMember] = useState(false);
  const [respondingInvitations, setRespondingInvitations] = useState<Record<number, 'accept' | 'decline'>>({});
  const [loading, setLoading] = useState(true);
  const [classDataAccountKey, setClassDataAccountKey] = useState<string | null>(null);
  const joinInFlightRef = useRef(false);
  const leaveInFlightRef = useRef(false);
  const removeInFlightRef = useRef(false);
  const createInFlightRef = useRef(false);
  const inviteInFlightRef = useRef(false);
  const invitationResponsesInFlightRef = useRef(new Set<number>());
  const classLoadGenerationRef = useRef(0);
  const mutationEpochRef = useRef(0);
  const mountedRef = useRef(true);
  const leaveDialogRef = useRef<HTMLDivElement | null>(null);
  const leaveCancelRef = useRef<HTMLButtonElement | null>(null);
  const leaveReturnFocusRef = useRef<HTMLElement | null>(null);
  const removeDialogRef = useRef<HTMLDivElement | null>(null);
  const removeCancelRef = useRef<HTMLButtonElement | null>(null);
  const removeReturnFocusRef = useRef<HTMLElement | null>(null);
  const [searchParams, setSearchParams] = useSearchParams();
  const auth = useAuth();
  const myId = auth.profile?.id;
  const verifiedAccountKey = auth.user && auth.profile
    && (!auth.profile.supabase_user_id || auth.profile.supabase_user_id === auth.user.id)
    ? `${auth.user.id}:${auth.profile.id}`
    : null;
  const verifiedAccountKeyRef = useRef<string | null>(verifiedAccountKey);
  verifiedAccountKeyRef.current = verifiedAccountKey;
  const activeShareScope = classShareScope(selectedGroup);
  const activeShareScopeRef = useRef<string | null>(activeShareScope);
  activeShareScopeRef.current = activeShareScope;

  useEffect(() => {
    setCopied('');
    setManualCopy(null);
  }, [activeShareScope]);

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
    if (member.is_current_user) return t('class.you');
    if (member.username) return `@${member.username}`;
    return member.display_name ?? t('class.member');
  };

  const isCurrentClassLoad = (generation: number) => (
    mountedRef.current && classLoadGenerationRef.current === generation
  );

  const captureMutationToken = (): ClassMutationToken | null => {
    const accountKey = verifiedAccountKeyRef.current;
    if (!accountKey) return null;
    return {
      accountKey,
      loadGeneration: classLoadGenerationRef.current,
      mutationEpoch: mutationEpochRef.current,
    };
  };

  const isCurrentMutationOwner = (token: ClassMutationToken) => (
    mountedRef.current
    && verifiedAccountKeyRef.current === token.accountKey
    && mutationEpochRef.current === token.mutationEpoch
  );

  const isCurrentMutation = (token: ClassMutationToken) => (
    isCurrentMutationOwner(token)
    && classLoadGenerationRef.current === token.loadGeneration
  );

  const selectGroup = async (groupId: number, requestedGeneration?: number) => {
    const generation = requestedGeneration ?? ++classLoadGenerationRef.current;
    if (isCurrentClassLoad(generation)) {
      setLoading(true);
      setCopied('');
      setManualCopy(null);
    }
    try {
      const group = await getEnsembleGroup(groupId);
      if (!isCurrentClassLoad(generation)) return;
      setSelectedGroup(group);
      setSummary(null);
      setReport(null);
      setRoster(null);
      setSummaryState('idle');
      setReportState('idle');
      setRosterState('idle');
      if (managesGroup(group)) {
        const [summaryResult, reportResult, rosterResult] = await Promise.allSettled([
          getEnsembleSummary(groupId),
          getEnsembleReport(groupId),
          getEnsembleRoster(groupId),
        ]);
        if (!isCurrentClassLoad(generation)) return;
        setSummary(summaryResult.status === 'fulfilled' ? summaryResult.value : null);
        setSummaryState(summaryResult.status === 'fulfilled' ? 'ready' : 'error');
        setReport(reportResult.status === 'fulfilled' ? reportResult.value : null);
        setReportState(reportResult.status === 'fulfilled' ? 'ready' : 'error');
        setRoster(rosterResult.status === 'fulfilled' ? rosterResult.value.students ?? [] : null);
        setRosterState(rosterResult.status === 'fulfilled' ? 'ready' : 'error');
      }
    } catch (error) {
      if (isCurrentClassLoad(generation)) {
        setEnsembleStatus(localizedError(error, 'class.errorLoad'));
      }
    } finally {
      if (isCurrentClassLoad(generation)) setLoading(false);
    }
  };

  const loadEverything = async (preferredGroupId?: number, requestedAccountKey = verifiedAccountKey) => {
    const generation = ++classLoadGenerationRef.current;
    if (isCurrentClassLoad(generation)) setLoading(true);
    try {
      const [groupsResult, invitesResult] = await Promise.allSettled([
        getEnsembleGroups(),
        getEnsembleInvitations(),
      ]);
      if (!isCurrentClassLoad(generation)) return;
      if (groupsResult.status === 'rejected') throw groupsResult.reason;
      const groupsData = groupsResult.value;
      const invitesData = invitesResult.status === 'fulfilled' ? invitesResult.value : null;
      setGroups(groupsData);
      setInvitations(invitesData?.invitations ?? []);
      setInvitationsState(invitesResult.status === 'fulfilled' ? 'ready' : 'error');
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
        setSummaryState('idle');
        setReportState('idle');
        setRosterState('idle');
      }
    } catch (error) {
      if (isCurrentClassLoad(generation)) {
        setEnsembleStatus(localizedError(error, 'class.errorLoad'));
      }
    } finally {
      if (isCurrentClassLoad(generation)) {
        setClassDataAccountKey(requestedAccountKey);
        setLoading(false);
      }
    }
  };

  const reloadForMutation = async (token: ClassMutationToken, preferredGroupId?: number) => {
    if (!isCurrentMutation(token)) return false;
    const reload = loadEverything(preferredGroupId, token.accountKey);
    const reloadGeneration = classLoadGenerationRef.current;
    await reload;
    return isCurrentMutationOwner(token) && classLoadGenerationRef.current === reloadGeneration;
  };

  const reloadGroupForMutation = async (token: ClassMutationToken, groupId: number) => {
    if (!isCurrentMutation(token)) return false;
    const reload = selectGroup(groupId);
    const reloadGeneration = classLoadGenerationRef.current;
    await reload;
    return isCurrentMutationOwner(token) && classLoadGenerationRef.current === reloadGeneration;
  };

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
      classLoadGenerationRef.current += 1;
    };
  }, []);

  useEffect(() => {
    classLoadGenerationRef.current += 1;
    mutationEpochRef.current += 1;
    joinInFlightRef.current = false;
    leaveInFlightRef.current = false;
    removeInFlightRef.current = false;
    createInFlightRef.current = false;
    inviteInFlightRef.current = false;
    invitationResponsesInFlightRef.current.clear();
    setClassDataAccountKey(null);
    setGroups([]);
    setSelectedGroup(null);
    setSummary(null);
    setReport(null);
    setRoster(null);
    setInvitations([]);
    setSummaryState('idle');
    setReportState('idle');
    setRosterState('idle');
    setInvitationsState('idle');
    setManualCopy(null);
    setAcceptInstruments({});
    setPendingRemove(null);
    setPendingLeave(null);
    const sharedCode = searchParams.get('join')?.trim().toUpperCase() ?? '';
    setJoinCodeInput(sharedCode);
    setJoinInstrument('');
    setNewGroupName('');
    setMemberUsername('');
    setInviteInstrument('');
    setShowJoin(Boolean(sharedCode));
    setShowCreate(false);
    setJoining(false);
    setLeavingGroup(false);
    setRemovingMember(false);
    setRotatingCode(false);
    setCreatingGroup(false);
    setInvitingMember(false);
    setRespondingInvitations({});
    setEnsembleStatus('');
    if (!verifiedAccountKey) {
      setLoading(false);
      return;
    }
    setLoading(true);
    void loadEverything(undefined, verifiedAccountKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [verifiedAccountKey]);

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
        if (leaveInFlightRef.current) return;
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

  useEffect(() => {
    if (!pendingRemove) return undefined;
    removeCancelRef.current?.focus();
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        if (removeInFlightRef.current) return;
        setPendingRemove(null);
        return;
      }
      if (event.key !== 'Tab' || !removeDialogRef.current) return;
      const focusable = Array.from(
        removeDialogRef.current.querySelectorAll<HTMLElement>(
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
      const returnFocus = removeReturnFocusRef.current;
      removeReturnFocusRef.current = null;
      if (returnFocus?.isConnected) returnFocus.focus();
    };
  }, [pendingRemove]);
  const respondToInvitation = async (invitation: EnsembleInvitation, accept: boolean) => {
    const chosenInstrument = acceptInstruments[invitation.member_id]
      ?? (isKnownInstrument(invitation.instrument_id) ? invitation.instrument_id : '');
    if (accept && !chosenInstrument) {
      setEnsembleStatus(t('class.chooseInstrumentFirst'));
      return;
    }
    if (invitationResponsesInFlightRef.current.has(invitation.member_id)) return;
    const token = captureMutationToken();
    if (!token) return;
    invitationResponsesInFlightRef.current.add(invitation.member_id);
    setRespondingInvitations((current) => ({
      ...current,
      [invitation.member_id]: accept ? 'accept' : 'decline',
    }));
    try {
      if (accept) {
        // The student's own instrument choice is set as part of accepting.
        await acceptEnsembleInvitation(
          invitation.member_id,
          chosenInstrument !== invitation.instrument_id ? chosenInstrument : undefined,
        );
      } else {
        await declineEnsembleInvitation(invitation.member_id);
      }
      if (!isCurrentMutation(token)) return;
      if (!await reloadForMutation(token, accept ? invitation.group_id : undefined)) return;
      setEnsembleStatus(t(accept ? 'class.joined' : 'class.declined', { name: invitation.group_name }));
    } catch (error) {
      if (isCurrentMutation(token)) {
        setEnsembleStatus(localizedError(error, 'class.errorInvitation'));
      }
    } finally {
      if (isCurrentMutationOwner(token)) {
        invitationResponsesInFlightRef.current.delete(invitation.member_id);
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
      setEnsembleStatus(t('class.enterCode'));
      return;
    }
    const token = captureMutationToken();
    if (!token) return;
    joinInFlightRef.current = true;
    setJoining(true);
    setEnsembleStatus(t('class.joining'));
    try {
      const result = await joinEnsembleByCode(code, joinInstrument || undefined);
      if (!isCurrentMutation(token)) return;
      setJoinCodeInput('');
      setJoinInstrument('');
      setShowJoin(false);
      if (!await reloadForMutation(token, result.group_id)) return;
      setEnsembleStatus(t('class.joined', { name: result.group_name }));
      if (searchParams.has('join')) {
        const next = new URLSearchParams(searchParams);
        next.delete('join');
        setSearchParams(next, { replace: true });
      }
    } catch (error) {
      if (!isCurrentMutation(token)) return;
      if (error instanceof Error && /conflicts with existing account or ensemble data/i.test(error.message)) {
        if (!await reloadForMutation(token)) return;
        setEnsembleStatus(t('class.alreadyJoined'));
      } else {
        setEnsembleStatus(localizedError(error, 'class.errorCode'));
      }
    } finally {
      if (isCurrentMutationOwner(token)) {
        joinInFlightRef.current = false;
        setJoining(false);
      }
    }
  };

  const createGroup = async () => {
    if (createInFlightRef.current) return;
    const groupName = newGroupName.trim();
    if (!groupName) {
      setEnsembleStatus(t('class.nameFirst'));
      return;
    }
    const token = captureMutationToken();
    if (!token) return;
    createInFlightRef.current = true;
    setCreatingGroup(true);
    try {
      const group = await createEnsembleGroup(groupName);
      if (!isCurrentMutation(token)) return;
      setNewGroupName('');
      setShowCreate(false);
      await auth.refreshProfile().catch(() => undefined);
      if (!isCurrentMutation(token)) return;
      if (!await reloadForMutation(token, group.id)) return;
      setEnsembleStatus(t('class.created', { name: group.name }));
    } catch (error) {
      if (isCurrentMutation(token)) {
        setEnsembleStatus(localizedError(error, 'class.errorCreate'));
      }
    } finally {
      if (isCurrentMutationOwner(token)) {
        createInFlightRef.current = false;
        setCreatingGroup(false);
      }
    }
  };

  const addMember = async () => {
    if (inviteInFlightRef.current) return;
    if (!selectedGroup?.id) {
      setEnsembleStatus(t('class.pickClass'));
      return;
    }
    if (!memberUsername.trim()) {
      setEnsembleStatus(t('class.usernameFirst'));
      return;
    }
    const groupId = selectedGroup.id;
    const username = memberUsername.trim();
    const instrumentId = inviteInstrument;
    const token = captureMutationToken();
    if (!token) return;
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
      if (!isCurrentMutation(token)) return;
      setMemberUsername('');
      setInviteInstrument('');
      if (!await reloadGroupForMutation(token, groupId)) return;
      setEnsembleStatus(t('class.inviteSent'));
    } catch (error) {
      if (isCurrentMutation(token)) {
        setEnsembleStatus(localizedError(error, 'class.errorInvite'));
      }
    } finally {
      if (isCurrentMutationOwner(token)) {
        inviteInFlightRef.current = false;
        setInvitingMember(false);
      }
    }
  };

  const doRemove = async () => {
    if (!selectedGroup?.id || !pendingRemove || removeInFlightRef.current) return;
    const { memberId, label } = pendingRemove;
    const groupId = selectedGroup.id;
    const token = captureMutationToken();
    if (!token) return;
    removeInFlightRef.current = true;
    setRemovingMember(true);
    try {
      await removeEnsembleMember(groupId, memberId);
      if (!isCurrentMutation(token)) return;
      if (!await reloadGroupForMutation(token, groupId)) return;
      setEnsembleStatus(t('class.removed', { name: label }));
    } catch (error) {
      if (isCurrentMutation(token)) {
        setEnsembleStatus(localizedError(error, 'class.errorRemove'));
      }
    } finally {
      if (isCurrentMutationOwner(token)) {
        removeInFlightRef.current = false;
        setRemovingMember(false);
        setPendingRemove(null);
      }
    }
  };

  const doLeave = async () => {
    if (!pendingLeave || leaveInFlightRef.current) return;
    const leaving = pendingLeave;
    const token = captureMutationToken();
    if (!token) return;
    leaveInFlightRef.current = true;
    setLeavingGroup(true);
    try {
      await leaveEnsembleGroup(leaving.groupId);
      if (!isCurrentMutation(token)) return;
      if (!await reloadForMutation(token)) return;
      setEnsembleStatus(t('class.left', { name: leaving.label }));
    } catch (error) {
      if (isCurrentMutation(token)) {
        setEnsembleStatus(localizedError(error, 'class.errorLeave'));
      }
    } finally {
      if (isCurrentMutationOwner(token)) {
        leaveInFlightRef.current = false;
        setLeavingGroup(false);
        setPendingLeave(null);
      }
    }
  };

  const rotateJoinCode = async () => {
    if (!selectedGroup?.id || !managesSelected || rotatingCode) return;
    const token = captureMutationToken();
    if (!token) return;
    setCopied('');
    setManualCopy(null);
    setRotatingCode(true);
    try {
      const result = await rotateEnsembleJoinCode(selectedGroup.id);
      if (!isCurrentMutation(token)) return;
      setSelectedGroup((current: any) => current?.id === result.group_id ? { ...current, join_code: result.join_code } : current);
      setGroups((current) => current.map((group) => group.id === result.group_id ? { ...group, join_code: result.join_code } : group));
      setCopied('');
      setManualCopy(null);
      setEnsembleStatus(t('class.codeRotated'));
    } catch (error) {
      if (isCurrentMutation(token)) {
        setCopied('');
        setManualCopy(null);
        setEnsembleStatus(localizedError(error, 'class.errorRotate'));
      }
    } finally {
      if (isCurrentMutationOwner(token)) setRotatingCode(false);
    }
  };
  const copyText = async (text: string, key: string) => {
    const scope = activeShareScopeRef.current;
    if (!scope) return;
    setManualCopy(null);
    if (await copyClassShareText(navigator.clipboard, text)) {
      if (activeShareScopeRef.current !== scope) return;
      setCopied(key);
      window.setTimeout(() => setCopied((current) => (current === key ? '' : current)), 1600);
      return;
    }
    if (activeShareScopeRef.current !== scope) return;
    setCopied('');
    setManualCopy({ scope, key, text });
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
  if (!verifiedAccountKey) {
    const returnPath = `/ensemble${searchParams.toString() ? `?${searchParams.toString()}` : ''}`;
    return (
      <ScreenContainer>
        <PageHeader title={t('nav.class')} description={t('class.description')} />
        <SectionCard title={t('class.signInTitle')}>
          <p className="muted-copy">{t('class.signInBody')}</p>
          {searchParams.get('join') && <p className="muted-copy">{t('class.practiceDisclosure')}</p>}
          {auth.configured ? (
            <Link to={gatewayPathWithReturn(returnPath)} className="primary-button ec-signin-btn" onClick={auth.exitGuest}>{t('auth.signInOrCreate')}</Link>
          ) : (
            <p className="settings-status" role="status">{t('class.cloudUnavailable')}</p>
          )}
          <div className="ec-preview" aria-hidden="true">
            <div className="ec-preview-head">
              <span className="ec-preview-tag">{t('class.preview')}</span>
              <span className="ec-preview-title">{t('class.previewName')}</span>
            </div>
            <div className="ec-roster">
              {SAMPLE_ROSTER.map((student) => (
                <div className="ec-student-card" key={student.name}>
                  <div className="ec-student-top">
                    <span className="ec-student-name">{student.name}</span>
                  </div>
                  <div className="ec-student-meta">
                    <span className="ec-meta"><em>{t('instrument.label')}</em>{t(`instrument.${student.instrument}` as MessageId)}</span>
                    <span className="ec-meta"><em>{t('class.lastPractice')}</em>{student.last === 'Today' ? t('class.today') : student.last === 'Yesterday' ? t('class.yesterday') : t('class.daysAgo', { count: formatNumber(2) })}</span>
                    <span className="ec-meta"><em>{t('class.thisWeek')}</em>{t('class.minutesShort', { count: formatNumber(student.minutes) })}</span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </SectionCard>
      </ScreenContainer>
    );
  }

  if (classDataAccountKey !== verifiedAccountKey) {
    return (
      <ScreenContainer>
        <PageHeader title={t('nav.class')} description={t('class.description')} />
        <p className="settings-status" role="status">{t('class.loadingAccount')}</p>
      </ScreenContainer>
    );
  }

  // ---- Signed in ----------------------------------------------------------
  const code = selectedGroup ? classCode(selectedGroup) : null;
  const origin = typeof window !== 'undefined' ? window.location.origin : '';
  const shareLink = code ? `${origin}/ensemble?join=${encodeURIComponent(code)}` : null;
  const leaveClassAction = canLeaveSelected && selectedGroup ? (
    <button
      className="ghost-button ec-leave-class ec-no-print"
      type="button"
      disabled={leavingGroup}
      aria-busy={leavingGroup}
      onClick={(event) => {
        leaveReturnFocusRef.current = event.currentTarget;
        setPendingLeave({ groupId: selectedGroup.id, label: selectedGroup.name });
      }}
    >
      <LogOut size={15} />
      {t('class.leave')}
    </button>
  ) : undefined;

  const renderStudentCard = (student: EnsembleRosterStudent) => {
    const invited = student.status === 'invited';
    const name = student.display_name ?? (student.username ? `@${student.username}` : t('class.student'));
    const onPitch = describeInTunePercent(student.in_tune_percentage);
    const tuning = describeAverageOff(student.average_abs_cents);
    return (
      <div className={`ec-student-card${invited ? ' ec-invited' : ''}`} key={student.member_id}>
        <div className="ec-student-top">
          <span className="ec-student-name">{name}</span>
          {invited && <span className="ec-badge ec-tone-amber">{t('class.invited')}</span>}
          <button
            className="ec-remove ec-no-print"
            type="button"
            onClick={(event) => {
              removeReturnFocusRef.current = event.currentTarget;
              setPendingRemove({ memberId: student.member_id, label: name });
            }}
          >
            <Trash2 size={15} />
            <span>{t('class.remove')}</span>
          </button>
        </div>
        {invited ? (
          <p className="ec-invited-note">{t('class.waitingInvite')}</p>
        ) : (
          <>
            <div className="ec-student-meta">
              <span className="ec-meta"><em>{t('instrument.label')}</em>{t(`instrument.${student.instrument_id}` as MessageId)}</span>
              <span className="ec-meta"><em>{t('class.lastPractice')}</em>{relativeWhen(student.last_practice_at, t, formatNumber)}</span>
              <span className="ec-meta"><em>{t('class.practiceTime')}</em>{t('class.minutesShort', { count: formatNumber(student.practice_minutes) })}</span>
            </div>
            {showAdvanced && (
              <div className="ec-advanced">
                <span className={`ec-stat ec-tone-${onPitch.tone}`}>
                  <em>{t('class.onPitch')}</em>
                  <strong><bdi dir="ltr">{student.in_tune_percentage != null ? `${Math.round(student.in_tune_percentage)}%` : '—'}</bdi></strong>
                </span>
                <span className={`ec-stat ec-tone-${tuning.tone}`}>
                  <em>{t('tuning.meter')}</em>
                  <strong>{t(tuning.tone === 'green' ? 'playAlong.grade.excellent' : tuning.tone === 'amber' ? 'playAlong.grade.close' : tuning.tone === 'red' ? 'playAlong.grade.off' : 'class.noPlays')}</strong>
                  {tuning.detail && <small>{t('class.centsOffAverage', { cents: formatNumber(Math.round(student.average_abs_cents ?? 0)) })}</small>}
                </span>
                <span className="ec-stat ec-tone-muted">
                  <em>{t('class.sessions')}</em>
                  <strong>{formatNumber(student.sessions_count)}</strong>
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
        title={t('nav.class')}
        description={t('class.description')}
        action={hasDirectorReport ? (
          <button className="ghost-button ec-no-print" onClick={handlePrint} type="button">
            <Printer size={18} />
            {t('class.printReport')}
          </button>
        ) : undefined}
      />

      {invitations.length > 0 && (
        <SectionCard title={t('class.youAreInvited')}>
          <div className="ec-invite-cards">
            {invitations.map((invitation) => {
              const chosen = acceptInstruments[invitation.member_id] ?? (isKnownInstrument(invitation.instrument_id) ? invitation.instrument_id : '');
              const pendingAction = respondingInvitations[invitation.member_id];
              return (
                <div className="ec-invite-card" key={invitation.member_id}>
                  <span className="ec-invite-icon"><Mail size={18} /></span>
                  <div className="ec-invite-copy">
                    <strong>{invitation.group_name}</strong>
                    <em>{invitation.director_name ? t('class.invitedBy', { name: invitation.director_name }) : t('class.invitedJoin')}</em>
                    <span className="ec-invite-role">{t('class.role', { role: invitationRoleLabel(invitation.role_in_group, t) })}</span>
                    <span className="ec-invite-role">{t('class.practiceDisclosure')}</span>
                  </div>
                  <label className="ec-select ec-accept-select">
                    <span>{t('class.yourInstrument')}</span>
                    <select
                      value={chosen}
                      onChange={(event) => setAcceptInstruments((prev) => ({ ...prev, [invitation.member_id]: event.target.value }))}
                      disabled={Boolean(pendingAction)}
                      aria-describedby={!chosen ? `ec-instrument-required-${invitation.member_id}` : undefined}
                    >
                      <option value="">{t('class.pickInstrument')}</option>
                      {INSTRUMENT_OPTIONS.map((id) => (
                        <option value={id} key={id}>{t(`instrument.${id}` as MessageId)}</option>
                      ))}
                    </select>
                    {!chosen && <small className="ec-instrument-required" id={`ec-instrument-required-${invitation.member_id}`}>{t('class.chooseBeforeAccept')}</small>}
                  </label>
                  <div className="ec-invite-actions">
                    <button className="primary-button" type="button" onClick={() => respondToInvitation(invitation, true)} disabled={Boolean(pendingAction) || !chosen}>
                      <Check size={16} />
                      {pendingAction === 'accept' ? t('class.joining') : t('class.accept')}
                    </button>
                    <button className="ghost-button" type="button" onClick={() => respondToInvitation(invitation, false)} disabled={Boolean(pendingAction)}>
                      <X size={16} />
                      {pendingAction === 'decline' ? t('class.declining') : t('class.decline')}
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        </SectionCard>
      )}
      {invitationsState === 'error' && (
        <p className="settings-status" role="status">{t('class.invitationsUnavailable')}</p>
      )}

      {ensembleStatus && <p className="settings-status" role="status" aria-live="polite">{ensembleStatus}</p>}

      {groups.length === 0 ? (
        <>
          <SectionCard title={t('class.joinYourClass')} eyebrow={t('class.forStudents')}>
            <div className="ec-empty">
              <span className="ec-empty-icon"><Users size={26} /></span>
              <p className="muted-copy">{t('class.enterCode')}</p>
              <div className="ec-create-row ec-no-print">
                <input
                  className="ec-input ec-code-input"
                  dir="ltr"
                  value={joinCodeInput}
                  onChange={(event) => setJoinCodeInput(event.target.value.toUpperCase())}
                  placeholder={t('class.codeExample')}
                  aria-label={t('class.code')}
                  autoCapitalize="characters"
                  maxLength={16}
                  disabled={joining}
                  onKeyDown={(event) => { if (event.key === 'Enter') joinByCode(); }}
                />
                <select className="ec-input" value={joinInstrument} onChange={(event) => setJoinInstrument(event.target.value)} aria-label={t('class.yourInstrument')} disabled={joining}>
                  <option value="">{t('class.yourInstrument')}</option>
                  {INSTRUMENT_OPTIONS.map((id) => (
                    <option key={id} value={id}>{t(`instrument.${id}` as MessageId)}</option>
                  ))}
                </select>
                <button className="primary-button" type="button" onClick={joinByCode} disabled={joinCodeInput.trim().length < 4 || joining}>
                  <UserPlus size={18} />
                  {joining ? t('class.joining') : t('class.join')}
                </button>
              </div>
              <p className="muted-copy">{t('class.practiceDisclosure')}</p>
              {auth.profile?.username && (
                <p className="ec-username-hint">
                  {t('class.noCodeUsername')} <strong><bdi dir="ltr">@{auth.profile.username}</bdi></strong>
                </p>
              )}
            </div>
          </SectionCard>
          <SectionCard title={t('class.startClass')} eyebrow={t('class.forTeachers')}>
            <div className="ec-empty">
              <p className="muted-copy">{t('class.startBody')}</p>
              <div className="ec-create-row ec-no-print">
                <input
                  className="ec-input"
                  dir="auto"
                  value={newGroupName}
                  onChange={(event) => setNewGroupName(event.target.value)}
                  placeholder={t('class.nameExample')}
                  aria-label={t('class.name')}
                  disabled={creatingGroup}
                  onKeyDown={(event) => { if (event.key === 'Enter') createGroup(); }}
                />
                <button className="primary-button" type="button" onClick={createGroup} disabled={!newGroupName.trim() || creatingGroup}>
                  <Plus size={18} />
                  {creatingGroup ? t('class.creating') : t('class.create')}
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
              {t('class.joinAnother')}
            </button>
            <button className="ghost-button" type="button" onClick={() => { setShowCreate((value) => !value); setShowJoin(false); }} aria-expanded={showCreate}>
              <Plus size={16} />
              {t('class.newClass')}
            </button>
          </div>

          {showJoin && (
            <SectionCard title={t('class.joinAnother')} className="ec-no-print">
              <div className="ec-create-row">
                <input
                  className="ec-input ec-code-input"
                  dir="ltr"
                  value={joinCodeInput}
                  onChange={(event) => setJoinCodeInput(event.target.value.toUpperCase())}
                  placeholder={t('class.code')}
                  aria-label={t('class.code')}
                  autoCapitalize="characters"
                  maxLength={16}
                  disabled={joining}
                  onKeyDown={(event) => { if (event.key === 'Enter') joinByCode(); }}
                />
                <select className="ec-input" value={joinInstrument} onChange={(event) => setJoinInstrument(event.target.value)} aria-label={t('class.yourInstrument')} disabled={joining}>
                  <option value="">{t('class.yourInstrument')}</option>
                  {INSTRUMENT_OPTIONS.map((id) => (
                    <option key={id} value={id}>{t(`instrument.${id}` as MessageId)}</option>
                  ))}
                </select>
                <button className="primary-button" type="button" onClick={joinByCode} disabled={joinCodeInput.trim().length < 4 || joining}>
                  <UserPlus size={18} />
                  {joining ? t('class.joining') : t('class.join')}
                </button>
              </div>
              <p className="muted-copy">{t('class.practiceDisclosure')}</p>
            </SectionCard>
          )}

          {showCreate && (
            <SectionCard className="ec-no-print">
              <div className="ec-create-row">
                <input
                  className="ec-input"
                  dir="auto"
                  value={newGroupName}
                  onChange={(event) => setNewGroupName(event.target.value)}
                  placeholder={t('class.newNameExample')}
                  aria-label={t('class.newName')}
                  disabled={creatingGroup}
                  onKeyDown={(event) => { if (event.key === 'Enter') createGroup(); }}
                />
                <button className="primary-button" type="button" onClick={createGroup} disabled={!newGroupName.trim() || creatingGroup}>
                  <Plus size={18} />
                  {creatingGroup ? t('class.creating') : t('class.create')}
                </button>
              </div>
            </SectionCard>
          )}

          {!selectedGroup ? (
            <SectionCard title={t('class.loading')}>
              <p className="muted-copy" role="status">{t('class.loadingSelected')}</p>
            </SectionCard>
          ) : managesSelected ? (
            <div className="ec-print-area">
              <SectionCard title={selectedGroup?.name ?? t('nav.class')} action={leaveClassAction}>
                <div className="ec-print-only ec-print-head">
                  <h2>{selectedGroup?.name ?? t('nav.class')}</h2>
                  <p>{t('class.reportDate', { date: formatDate(new Date(), { dateStyle: 'medium' }) })}</p>
                </div>

                <div className="ec-join ec-no-print">
                  <div className="ec-join-main">
                    <span className="ec-join-label">{t('class.code')}</span>
                    <span className={`ec-join-code${code ? '' : ' unavailable'}`}><bdi dir="ltr">{code ?? t('class.unavailable')}</bdi></span>
                    <span className="ec-join-help">
                      {t(code ? 'class.codeHelp' : 'class.createCodeHelp')}
                    </span>
                  </div>
                  <div className="ec-join-actions">
                    <button className="ghost-button" type="button" onClick={() => code && copyText(code, 'code')} disabled={!code}>
                      <Copy size={15} />
                      {copied === 'code' ? t('legal.copied') : t('class.copyCode')}
                    </button>
                    <button className="ghost-button" type="button" onClick={() => shareLink && copyText(shareLink, 'link')} disabled={!shareLink}>
                      <Link2 size={15} />
                      {copied === 'link' ? t('legal.copied') : t('class.shareLink')}
                    </button>
                    <button className="ghost-button" type="button" onClick={rotateJoinCode} disabled={rotatingCode}>
                      <RefreshCw size={15} />
                      {rotatingCode ? t('class.rotating') : t(code ? 'class.rotateCode' : 'class.createCode')}
                    </button>
                  </div>
                  {manualCopy?.scope === activeShareScope && (
                    <label className="ec-field ec-manual-copy">
                      <span>{t('class.copyManually')}</span>
                      <input
                        dir="ltr"
                        readOnly
                        value={manualCopy.text}
                        onFocus={(event) => event.currentTarget.select()}
                        aria-label={t('class.copyManually')}
                      />
                    </label>
                  )}
                </div>

                <div className="ec-invite-row ec-no-print">
                  <label className="ec-select">
                    <span>{t('instrument.label')}</span>
                    <select value={inviteInstrument} onChange={(event) => setInviteInstrument(event.target.value)} disabled={invitingMember}>
                      <option value="">{t('class.chooseOptional')}</option>
                      {INSTRUMENT_OPTIONS.map((id) => (
                        <option value={id} key={id}>{t(`instrument.${id}` as MessageId)}</option>
                      ))}
                    </select>
                  </label>
                  <label className="ec-field">
                    <span>{t('class.addByUsername')}</span>
                    <input
                      className="ec-input"
                      dir="ltr"
                      value={memberUsername}
                      onChange={(event) => setMemberUsername(event.target.value.toLowerCase())}
                      placeholder="student-username"
                      disabled={invitingMember}
                      onKeyDown={(event) => { if (event.key === 'Enter') addMember(); }}
                    />
                  </label>
                  <button className="primary-button ec-send-invite" type="button" onClick={addMember} disabled={!memberUsername.trim() || invitingMember}>
                    <UserPlus size={17} />
                    {invitingMember ? t('class.sending') : t('class.sendInvite')}
                  </button>
                </div>

                {rosterState === 'error' ? (
                  <p className="muted-copy" role="status">{t('class.rosterUnavailable')}</p>
                ) : rosterState === 'ready' && roster && roster.length > 0 ? (
                  <>
                    <div className="ec-roster-head">
                      <span className="ec-roster-count">{t('class.studentCount', { count: roster.length })}</span>
                      <button
                        className={`ec-advanced-toggle ec-no-print ${showAdvanced ? 'open' : ''}`}
                        type="button"
                        onClick={() => setShowAdvanced((value) => !value)}
                        aria-pressed={showAdvanced}
                      >
                        <SlidersHorizontal size={14} />
                        {t('sessionReview.advanced')}
                        <ChevronDown size={14} className="ec-caret" />
                      </button>
                    </div>
                    <div className="ec-roster">
                      {roster.map(renderStudentCard)}
                    </div>
                    {showAdvanced && (
                      <p className="ec-cents-note">{t('class.centsHelp')}</p>
                    )}
                  </>
                ) : rosterState === 'ready' ? (
                  <p className="muted-copy">{t('class.noStudents')}</p>
                ) : null}
              </SectionCard>

              {(summaryState !== 'idle' || reportState !== 'idle') && (
                <>
                  <SectionCard title={t('class.sections')}>
                    {summaryState === 'error' ? (
                      <p className="muted-copy" role="status">{t('class.summaryUnavailable')}</p>
                    ) : <div className="ec-sections">
                      {(summary?.sections ?? []).map((section: any) => {
                        const tuning = describeAverageOff(section.average_abs_cents);
                        return (
                          <article className="ec-section" key={section.instrument_id}>
                            <span className="ec-section-name">{t(`instrument.${section.instrument_id}` as MessageId)}</span>
                            <strong className={`ec-tone-${tuning.tone}`}>{t(tuning.tone === 'green' ? 'playAlong.grade.excellent' : tuning.tone === 'amber' ? 'playAlong.grade.close' : tuning.tone === 'red' ? 'playAlong.grade.off' : 'class.noPlays')}</strong>
                            <p>{t('class.sectionSummary', { sessions: formatNumber(section.session_count), minutes: formatNumber(section.practice_minutes) })}</p>
                          </article>
                        );
                      })}
                      {(summary?.sections ?? []).length === 0 && (
                        <p className="muted-copy">{t('class.sectionEmpty')}</p>
                      )}
                    </div>}
                  </SectionCard>

                  {reportState === 'error' && (
                    <SectionCard title={t('sessionReview.nextWork')}>
                      <p className="muted-copy" role="status">{t('class.reportUnavailable')}</p>
                    </SectionCard>
                  )}

                  {reportState === 'ready' && report?.recommended_rehearsal_focus && (
                    <SectionCard title={t('sessionReview.nextWork')}>
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

                  {reportState === 'ready' && (report?.top_problem_notes ?? []).length > 0 && (
                    <SectionCard title={t('class.notesFocus')}>
                      <NoteStatsTable rows={report.top_problem_notes ?? []} />
                    </SectionCard>
                  )}
                </>
              )}
            </div>
          ) : (
            <SectionCard
              title={selectedGroup?.name ?? t('nav.class')}
              action={leaveClassAction}
            >
              <div className="ec-roster">
                {(selectedGroup?.members ?? []).map((member: any) => (
                  <div className="ec-student-card" key={member.id}>
                    <div className="ec-student-top">
                      <span className="ec-student-name">{memberLabel(member)}</span>
                      {member.status === 'invited' && <span className="ec-badge ec-tone-amber">{t('class.invited')}</span>}
                    </div>
                    <div className="ec-student-meta">
                      <span className="ec-meta"><em>{t('instrument.label')}</em>{t(`instrument.${member.instrument_id}` as MessageId)}</span>
                    </div>
                  </div>
                ))}
                {(selectedGroup?.members ?? []).length === 0 && <p className="muted-copy">{t('class.noOneElse')}</p>}
              </div>
            </SectionCard>
          )}
        </>
      )}

      {pendingRemove && (
        <div className="ec-modal-overlay ec-no-print" role="presentation" onClick={() => { if (!removingMember) setPendingRemove(null); }}>
          <div
            className="ec-modal"
            role="dialog"
            aria-modal="true"
            aria-busy={removingMember}
            aria-labelledby="ec-remove-title"
            ref={removeDialogRef}
            onClick={(event) => event.stopPropagation()}
          >
            <h3 id="ec-remove-title">{t('class.removeTitle', { name: pendingRemove.label })}</h3>
            <p className="muted-copy">{t('class.removeBody')}</p>
            <div className="ec-modal-actions">
              <button className="ghost-button" type="button" ref={removeCancelRef} onClick={() => setPendingRemove(null)} disabled={removingMember}>{t('common.cancel')}</button>
              <button className="ec-danger-btn" type="button" onClick={doRemove} disabled={removingMember}>
                {removingMember ? t('class.removing') : t('class.remove')}
              </button>
            </div>
          </div>
        </div>
      )}

      {pendingLeave && (
        <div
          className="ec-modal-overlay ec-no-print"
          role="presentation"
          onClick={() => { if (!leavingGroup) setPendingLeave(null); }}
        >
          <div
            className="ec-modal"
            role="dialog"
            aria-modal="true"
            aria-busy={leavingGroup}
            aria-labelledby="ec-leave-title"
            ref={leaveDialogRef}
            onClick={(event) => event.stopPropagation()}
          >
            <h3 id="ec-leave-title">{t('class.leaveTitle', { name: pendingLeave.label })}</h3>
            <p className="muted-copy">{t('class.leaveBody')}</p>
            <div className="ec-modal-actions">
              <button className="ghost-button" type="button" ref={leaveCancelRef} onClick={() => setPendingLeave(null)} disabled={leavingGroup}>{t('common.cancel')}</button>
              <button className="ec-danger-btn" type="button" onClick={doLeave} disabled={leavingGroup}>
                {leavingGroup ? t('class.leaving') : t('class.leave')}
              </button>
            </div>
          </div>
        </div>
      )}
    </ScreenContainer>
  );
}
