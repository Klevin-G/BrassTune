import { Check, ChevronDown, Copy, Link2, LogOut, Mail, Plus, Printer, RefreshCw, Search, SlidersHorizontal, Trash2, UserPlus, Users, X } from 'lucide-react';
import { useDeferredValue, useEffect, useMemo, useRef, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import {
  ApiRequestError,
  acceptEnsembleInvitation,
  addEnsembleMemberByUsername,
  createEnsembleGroup,
  declineEnsembleInvitation,
  enableEnsembleSharingConsent,
  friendlyUserFacingError,
  getEnsembleGroup,
  getEnsembleGroups,
  getEnsembleInvitations,
  getEnsembleMyProgress,
  getEnsembleReport,
  getEnsembleRoster,
  getEnsembleSummary,
  joinEnsembleByCode,
  leaveEnsembleGroup,
  removeEnsembleMember,
  rotateEnsembleJoinCode,
  type EnsembleInvitation,
  type EnsembleGroup,
  type EnsembleMyProgress,
  type EnsembleReport,
  type EnsembleRosterStudent,
  type EnsembleSummary,
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
type ClassResourceState = 'idle' | 'loading' | 'ready' | 'error';
type TopLevelState = 'loading' | 'ready' | 'error';
export type RosterSort = 'name' | 'last_practice' | 'weekly_minutes';
export type RosterInactivityFilter = 'all' | 'active_week' | 'needs_attention';

type ClassMutationToken = {
  accountKey: string;
  loadGeneration: number;
  mutationEpoch: number;
};

// Plain-language read of an average absolute cents deviation (how far off, on average).
function describeAverageOff(absCents: number | null | undefined): { tone: Tone } {
  if (absCents == null || Number.isNaN(absCents)) return { tone: 'muted' };
  if (absCents <= 8) return { tone: 'green' };
  if (absCents <= 18) return { tone: 'amber' };
  return { tone: 'red' };
}

function classCode(group: Pick<EnsembleGroup, 'join_code'> | null | undefined): string | null {
  const existing = group?.join_code;
  return typeof existing === 'string' && existing.trim() ? existing.trim().toUpperCase() : null;
}

export function classShareScope(group: Pick<EnsembleGroup, 'id' | 'join_code'> | null | undefined): string | null {
  if (!group) return null;
  const code = classCode(group);
  return Number.isInteger(group.id) && code ? `${group.id}:${code}` : null;
}

function invitationRoleLabel(role: string, t: ReturnType<typeof useI18n>['t']): string {
  if (role === 'assistant' || role === 'director') return t('class.roleAssistant');
  return t('class.student');
}

function viewerRoleLabel(role: EnsembleGroup['viewer_role'], t: ReturnType<typeof useI18n>['t']): string {
  if (role === 'owner') return t('class.forTeachers');
  if (role === 'assistant') return t('class.roleAssistant');
  if (role === 'admin_observer') return t('settings.admin');
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

export function classViewMode(group: Pick<EnsembleGroup, 'viewer_can_manage' | 'viewer_can_view_roster' | 'viewer_can_view_class_analytics'>): 'owner' | 'assistant' | 'student' {
  if (group.viewer_can_manage) return 'owner';
  if (group.viewer_can_view_roster || group.viewer_can_view_class_analytics) return 'assistant';
  return 'student';
}

export function classResourcePlan(group: Pick<EnsembleGroup, 'viewer_role' | 'viewer_can_view_roster' | 'viewer_can_view_class_analytics' | 'viewer_has_aggregate_sharing_consent'>) {
  const requiresConsent = classViewerNeedsSharingConsent(group);
  return {
    analytics: group.viewer_can_view_class_analytics && !requiresConsent,
    roster: group.viewer_can_view_roster && !requiresConsent,
    ownProgress: group.viewer_role === 'student' && !requiresConsent,
  };
}

export function classViewerNeedsSharingConsent(
  group: Pick<EnsembleGroup, 'viewer_role' | 'viewer_has_aggregate_sharing_consent'>,
): boolean {
  return (group.viewer_role === 'student' || group.viewer_role === 'assistant')
    && !group.viewer_has_aggregate_sharing_consent;
}

export function isClassConsentRequiredError(error: unknown): boolean {
  return error instanceof ApiRequestError && (error.status === 403 || error.status === 409);
}

export function acquireSynchronousClassGuard(guard: { current: boolean }): boolean {
  if (guard.current) return false;
  guard.current = true;
  return true;
}

export function filterAndSortClassRoster(
  roster: EnsembleRosterStudent[],
  options: {
    search: string;
    instrument: string;
    inactivity: RosterInactivityFilter;
    status: 'all' | 'active' | 'invited';
    sort: RosterSort;
    locale: string;
  },
): EnsembleRosterStudent[] {
  const search = options.search.trim().toLocaleLowerCase(options.locale);
  const rows = roster.filter((student) => {
    const searchable = [student.display_name, student.username, student.instrument_id]
      .filter(Boolean)
      .join(' ')
      .toLocaleLowerCase(options.locale);
    if (search && !searchable.includes(search)) return false;
    if (options.instrument !== 'all' && student.instrument_id !== options.instrument) return false;
    if (options.status !== 'all' && student.status !== options.status) return false;
    if (options.inactivity === 'active_week' && !['active_today', 'active_this_week'].includes(student.inactivity.state)) return false;
    if (options.inactivity === 'needs_attention' && !['inactive_7d', 'no_practice_since_joining'].includes(student.inactivity.state)) return false;
    return true;
  });
  return rows.sort((left, right) => {
    if (options.sort === 'weekly_minutes') return right.current_7d.practice_minutes - left.current_7d.practice_minutes;
    if (options.sort === 'last_practice') {
      const leftTime = left.last_practice_at
        ? new Date(left.last_practice_at).getTime()
        : -(left.inactivity.days_since_last_practice ?? Number.MAX_SAFE_INTEGER);
      const rightTime = right.last_practice_at
        ? new Date(right.last_practice_at).getTime()
        : -(right.inactivity.days_since_last_practice ?? Number.MAX_SAFE_INTEGER);
      return rightTime - leftTime;
    }
    const leftName = left.display_name ?? left.username ?? '';
    const rightName = right.display_name ?? right.username ?? '';
    return leftName.localeCompare(rightName, options.locale, { sensitivity: 'base' });
  });
}

export function classRosterKey(student: EnsembleRosterStudent, fallbackIndex: number): string {
  return student.roster_row_id
    ?? (student.member_id != null ? `member:${student.member_id}` : `legacy:${student.display_name ?? ''}:${student.instrument_id}:${fallbackIndex}`);
}

export function showsTopLevelClassRetry(
  classDataAccountKey: string | null,
  verifiedAccountKey: string | null,
  state: TopLevelState,
): boolean {
  return Boolean(verifiedAccountKey && classDataAccountKey === verifiedAccountKey && state === 'error');
}

export function EnsemblePage() {
  const { locale, dir, t, formatDate, formatNumber } = useI18n();
  const localizedError = (error: unknown, id: MessageId) => locale === 'en' ? friendlyUserFacingError(error, t(id)) : t(id);
  const [summary, setSummary] = useState<EnsembleSummary | null>(null);
  const [report, setReport] = useState<EnsembleReport | null>(null);
  const [myProgress, setMyProgress] = useState<EnsembleMyProgress | null>(null);
  const [roster, setRoster] = useState<EnsembleRosterStudent[] | null>(null);
  const [invitations, setInvitations] = useState<EnsembleInvitation[]>([]);
  const [groups, setGroups] = useState<EnsembleGroup[]>([]);
  const [selectedGroup, setSelectedGroup] = useState<EnsembleGroup | null>(null);
  const [selectedGroupErrorId, setSelectedGroupErrorId] = useState<number | null>(null);
  const [newGroupName, setNewGroupName] = useState('');
  const [memberUsername, setMemberUsername] = useState('');
  const [inviteInstrument, setInviteInstrument] = useState('');
  const [inviteRole, setInviteRole] = useState<'student' | 'assistant'>('student');
  const [ensembleStatus, setEnsembleStatus] = useState('');
  const [showCreate, setShowCreate] = useState(false);
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [rosterSearch, setRosterSearch] = useState('');
  const [rosterSort, setRosterSort] = useState<RosterSort>('name');
  const [rosterInstrument, setRosterInstrument] = useState('all');
  const [rosterInactivity, setRosterInactivity] = useState<RosterInactivityFilter>('all');
  const [rosterStatus, setRosterStatus] = useState<'all' | 'active' | 'invited'>('all');
  const [copied, setCopied] = useState('');
  const [manualCopy, setManualCopy] = useState<{ scope: string; key: string; text: string } | null>(null);
  const [summaryState, setSummaryState] = useState<ClassResourceState>('idle');
  const [reportState, setReportState] = useState<ClassResourceState>('idle');
  const [rosterState, setRosterState] = useState<ClassResourceState>('idle');
  const [progressState, setProgressState] = useState<ClassResourceState>('idle');
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
  const [enablingSharing, setEnablingSharing] = useState(false);
  const [consentRepairRequired, setConsentRepairRequired] = useState(false);
  const [respondingInvitations, setRespondingInvitations] = useState<Record<number, 'accept' | 'decline'>>({});
  const [loading, setLoading] = useState(true);
  const [topLevelState, setTopLevelState] = useState<TopLevelState>('loading');
  const [classDataAccountKey, setClassDataAccountKey] = useState<string | null>(null);
  const joinInFlightRef = useRef(false);
  const leaveInFlightRef = useRef(false);
  const removeInFlightRef = useRef(false);
  const createInFlightRef = useRef(false);
  const inviteInFlightRef = useRef(false);
  const rotateInFlightRef = useRef(false);
  const enableSharingInFlightRef = useRef(false);
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

  const selectedViewMode = selectedGroup ? classViewMode(selectedGroup) : null;
  const managesSelected = selectedViewMode === 'owner';
  const canLeaveSelected = Boolean(selectedGroup?.viewer_can_leave);
  const hasDirectorReport = Boolean(selectedGroup?.viewer_can_manage && report);
  const needsSharingConsent = Boolean(
    selectedGroup && (classViewerNeedsSharingConsent(selectedGroup) || consentRepairRequired),
  );

  const deferredRosterSearch = useDeferredValue(rosterSearch.trim().toLocaleLowerCase(locale));
  const rosterInstruments = useMemo(
    () => [...new Set((roster ?? []).map((student) => student.instrument_id))].sort(),
    [roster],
  );
  const visibleRoster = useMemo(() => {
    return filterAndSortClassRoster(roster ?? [], {
      search: deferredRosterSearch,
      instrument: rosterInstrument,
      inactivity: rosterInactivity,
      status: rosterStatus,
      sort: rosterSort,
      locale,
    });
  }, [deferredRosterSearch, locale, roster, rosterInactivity, rosterInstrument, rosterSort, rosterStatus]);

  const inactivityLabel = (student: Pick<EnsembleRosterStudent, 'inactivity'>) => {
    if (student.inactivity.state === 'active_today') return t('class.today');
    if (student.inactivity.state === 'active_this_week') return t('class.thisWeek');
    if (student.inactivity.state === 'no_practice_since_joining') return t('class.noPlays');
    return t('class.daysAgo', { count: formatNumber(student.inactivity.days_since_last_practice ?? 7) });
  };

  const signedDelta = (value: number) => `${value > 0 ? '+' : ''}${formatNumber(value)}`;

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

  const loadGroupResources = async (group: EnsembleGroup, generation: number) => {
    const plan = classResourcePlan(group);
    const canLoadAnalytics = plan.analytics;
    const canLoadRoster = plan.roster;
    const canLoadOwnProgress = plan.ownProgress;
    setSummaryState(canLoadAnalytics ? 'loading' : 'idle');
    setReportState(canLoadAnalytics ? 'loading' : 'idle');
    setRosterState(canLoadRoster ? 'loading' : 'idle');
    setProgressState(canLoadOwnProgress ? 'loading' : 'idle');

    const [summaryResult, reportResult, rosterResult, progressResult] = await Promise.allSettled([
      canLoadAnalytics ? getEnsembleSummary(group.id) : Promise.resolve(null),
      canLoadAnalytics ? getEnsembleReport(group.id) : Promise.resolve(null),
      canLoadRoster ? getEnsembleRoster(group.id) : Promise.resolve(null),
      canLoadOwnProgress ? getEnsembleMyProgress(group.id) : Promise.resolve(null),
    ]);
    if (!isCurrentClassLoad(generation)) return;
    const consentFailure = [summaryResult, reportResult, rosterResult, progressResult]
      .some((result) => result.status === 'rejected' && isClassConsentRequiredError(result.reason));
    setConsentRepairRequired(consentFailure);

    setSummary(summaryResult.status === 'fulfilled' ? summaryResult.value : null);
    setSummaryState(canLoadAnalytics ? (summaryResult.status === 'fulfilled' ? 'ready' : 'error') : 'idle');
    setReport(reportResult.status === 'fulfilled' ? reportResult.value : null);
    setReportState(canLoadAnalytics ? (reportResult.status === 'fulfilled' ? 'ready' : 'error') : 'idle');
    setRoster(rosterResult.status === 'fulfilled' ? rosterResult.value?.students ?? null : null);
    setRosterState(canLoadRoster ? (rosterResult.status === 'fulfilled' ? 'ready' : 'error') : 'idle');
    setMyProgress(progressResult.status === 'fulfilled' ? progressResult.value : null);
    setProgressState(canLoadOwnProgress ? (progressResult.status === 'fulfilled' ? 'ready' : 'error') : 'idle');
  };

  const selectGroup = async (groupId: number, requestedGeneration?: number) => {
    const generation = requestedGeneration ?? ++classLoadGenerationRef.current;
    if (isCurrentClassLoad(generation)) {
      setLoading(true);
      setSelectedGroupErrorId(null);
      setCopied('');
      setManualCopy(null);
    }
    try {
      const group = await getEnsembleGroup(groupId);
      if (!isCurrentClassLoad(generation)) return;
      setSelectedGroupErrorId(null);
      setConsentRepairRequired(false);
      setSelectedGroup(group);
      setSummary(null);
      setReport(null);
      setMyProgress(null);
      setRoster(null);
      setSummaryState('idle');
      setReportState('idle');
      setRosterState('idle');
      setProgressState('idle');
      await loadGroupResources(group, generation);
    } catch (error) {
      if (isCurrentClassLoad(generation)) {
        setSelectedGroup(null);
        setSelectedGroupErrorId(groupId);
        setEnsembleStatus(localizedError(error, 'class.errorLoad'));
      }
    } finally {
      if (isCurrentClassLoad(generation)) setLoading(false);
    }
  };

  const loadEverything = async (preferredGroupId?: number, requestedAccountKey = verifiedAccountKey) => {
    const generation = ++classLoadGenerationRef.current;
    if (isCurrentClassLoad(generation)) {
      setLoading(true);
      setTopLevelState('loading');
    }
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
      setTopLevelState('ready');
      setInvitations(invitesData?.invitations ?? []);
      setInvitationsState(invitesResult.status === 'fulfilled' ? 'ready' : 'error');
      const nextGroup = groupsData.find((group) => group.id === preferredGroupId)
        ?? groupsData.find((group) => group.id === selectedGroup?.id)
        ?? groupsData[0];
      if (nextGroup) {
        await selectGroup(nextGroup.id, generation);
      } else {
        setSelectedGroup(null);
        setSelectedGroupErrorId(null);
        setSummary(null);
        setReport(null);
        setMyProgress(null);
        setRoster(null);
        setSummaryState('idle');
        setReportState('idle');
        setRosterState('idle');
        setProgressState('idle');
      }
    } catch (error) {
      if (isCurrentClassLoad(generation)) {
        setTopLevelState('error');
        setGroups([]);
        setSelectedGroup(null);
        setSelectedGroupErrorId(null);
        setSummary(null);
        setReport(null);
        setMyProgress(null);
        setRoster(null);
      }
    } finally {
      if (isCurrentClassLoad(generation)) {
        setClassDataAccountKey(requestedAccountKey);
        setLoading(false);
      }
    }
  };

  const retryResource = async (resource: 'roster' | 'summary' | 'report' | 'progress') => {
    const group = selectedGroup;
    const generation = classLoadGenerationRef.current;
    if (!group || !isCurrentClassLoad(generation)) return;
    const stateSetter = resource === 'roster' ? setRosterState
      : resource === 'summary' ? setSummaryState
        : resource === 'report' ? setReportState
          : setProgressState;
    stateSetter('loading');
    try {
      if (resource === 'roster') {
        const result = await getEnsembleRoster(group.id);
        if (!isCurrentClassLoad(generation) || selectedGroup?.id !== group.id) return;
        setRoster(result.students);
      } else if (resource === 'summary') {
        const result = await getEnsembleSummary(group.id);
        if (!isCurrentClassLoad(generation) || selectedGroup?.id !== group.id) return;
        setSummary(result);
      } else if (resource === 'report') {
        const result = await getEnsembleReport(group.id);
        if (!isCurrentClassLoad(generation) || selectedGroup?.id !== group.id) return;
        setReport(result);
      } else {
        const result = await getEnsembleMyProgress(group.id);
        if (!isCurrentClassLoad(generation) || selectedGroup?.id !== group.id) return;
        setMyProgress(result);
      }
      stateSetter('ready');
    } catch (error) {
      if (isCurrentClassLoad(generation)) {
        if (isClassConsentRequiredError(error)) {
          setConsentRepairRequired(true);
          stateSetter('idle');
        } else {
          stateSetter('error');
        }
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
    rotateInFlightRef.current = false;
    enableSharingInFlightRef.current = false;
    invitationResponsesInFlightRef.current.clear();
    setClassDataAccountKey(null);
    setGroups([]);
    setSelectedGroup(null);
    setSelectedGroupErrorId(null);
    setSummary(null);
    setReport(null);
    setMyProgress(null);
    setRoster(null);
    setInvitations([]);
    setSummaryState('idle');
    setReportState('idle');
    setRosterState('idle');
    setProgressState('idle');
    setInvitationsState('idle');
    setManualCopy(null);
    setRosterSearch('');
    setRosterSort('name');
    setRosterInstrument('all');
    setRosterInactivity('all');
    setRosterStatus('all');
    setAcceptInstruments({});
    setPendingRemove(null);
    setPendingLeave(null);
    const sharedCode = searchParams.get('join')?.trim().toUpperCase() ?? '';
    setJoinCodeInput(sharedCode);
    setJoinInstrument('');
    setNewGroupName('');
    setMemberUsername('');
    setInviteInstrument('');
    setInviteRole('student');
    setShowJoin(Boolean(sharedCode));
    setShowCreate(false);
    setJoining(false);
    setLeavingGroup(false);
    setRemovingMember(false);
    setRotatingCode(false);
    setCreatingGroup(false);
    setInvitingMember(false);
    setEnablingSharing(false);
    setConsentRepairRequired(false);
    setRespondingInvitations({});
    setEnsembleStatus('');
    setTopLevelState(verifiedAccountKey ? 'loading' : 'ready');
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
        role_in_group: inviteRole,
      });
      if (!isCurrentMutation(token)) return;
      setMemberUsername('');
      setInviteInstrument('');
      setInviteRole('student');
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

  const enableSharing = async () => {
    if (!selectedGroup?.id || !acquireSynchronousClassGuard(enableSharingInFlightRef)) return;
    const groupId = selectedGroup.id;
    const token = captureMutationToken();
    if (!token) {
      enableSharingInFlightRef.current = false;
      return;
    }
    setEnablingSharing(true);
    try {
      await enableEnsembleSharingConsent(groupId);
      if (!isCurrentMutation(token)) return;
      setConsentRepairRequired(false);
      if (!await reloadGroupForMutation(token, groupId)) return;
      setEnsembleStatus(t('class.sharingEnabled'));
    } catch (error) {
      if (isCurrentMutation(token)) setEnsembleStatus(localizedError(error, 'class.sharingEnableError'));
    } finally {
      if (isCurrentMutationOwner(token)) {
        enableSharingInFlightRef.current = false;
        setEnablingSharing(false);
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
    if (!selectedGroup?.id || !managesSelected || !acquireSynchronousClassGuard(rotateInFlightRef)) return;
    const token = captureMutationToken();
    if (!token) {
      rotateInFlightRef.current = false;
      return;
    }
    setCopied('');
    setManualCopy(null);
    setRotatingCode(true);
    try {
      const result = await rotateEnsembleJoinCode(selectedGroup.id);
      if (!isCurrentMutation(token)) return;
      setSelectedGroup((current) => current?.id === result.group_id ? { ...current, join_code: result.join_code } : current);
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
      if (isCurrentMutationOwner(token)) {
        rotateInFlightRef.current = false;
        setRotatingCode(false);
      }
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

  if (showsTopLevelClassRetry(classDataAccountKey, verifiedAccountKey, topLevelState)) {
    return (
      <ScreenContainer>
        <PageHeader title={t('nav.class')} description={t('class.description')} />
        <SectionCard title={t('class.errorLoad')}>
          <p className="muted-copy" role="alert">{t('class.loadFailedBody')}</p>
          <button className="primary-button" type="button" onClick={() => void loadEverything()}>
            <RefreshCw size={17} />
            {t('auth.tryAgain')}
          </button>
        </SectionCard>
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

  const renderStudentCard = (student: EnsembleRosterStudent, fallbackIndex: number) => {
    const invited = student.status === 'invited';
    const name = student.display_name ?? (student.username ? `@${student.username}` : t('class.student'));
    const onPitch = describeInTunePercent(student.in_tune_percentage);
    const tuning = describeAverageOff(student.average_abs_cents);
    return (
      <div className={`ec-student-card${invited ? ' ec-invited' : ''}`} key={classRosterKey(student, fallbackIndex)}>
        <div className="ec-student-top">
          <span className="ec-student-name">{name}</span>
          {invited && <span className="ec-badge ec-tone-amber">{t('class.invited')}</span>}
          {selectedGroup?.viewer_can_manage && student.member_id != null && (
            <button
              className="ec-remove ec-no-print"
              type="button"
              onClick={(event) => {
                removeReturnFocusRef.current = event.currentTarget;
                setPendingRemove({ memberId: student.member_id as number, label: name });
              }}
            >
              <Trash2 size={15} />
              <span>{t('class.remove')}</span>
            </button>
          )}
        </div>
        {invited ? (
          <p className="ec-invited-note">{t('class.waitingInvite')}</p>
        ) : (
          <>
            <div className="ec-student-meta">
              <span className="ec-meta"><em>{t('instrument.label')}</em>{t(`instrument.${student.instrument_id}` as MessageId)}</span>
              <span className="ec-meta"><em>{t('class.lastPractice')}</em>{relativeWhen(student.last_practice_at, t, formatNumber)}</span>
              <span className="ec-meta"><em>{t('class.thisWeek')}</em>{t('class.minutesShort', { count: formatNumber(student.current_7d.practice_minutes) })}</span>
              <span className="ec-meta"><em>{t('class.weeklyTrend')}</em>{t('class.minutesDelta', { count: signedDelta(student.delta.practice_minutes) })}</span>
              <span className={`ec-meta ec-inactivity ec-inactivity-${student.inactivity.state}`}><em>{t('class.lastPractice')}</em>{inactivityLabel(student)}</span>
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
                  {student.average_abs_cents != null && <small>{t('class.centsOffAverage', { cents: formatNumber(Math.round(student.average_abs_cents)) })}</small>}
                </span>
                <span className="ec-stat ec-tone-muted">
                  <em>{t('class.sessions')}</em>
                  <strong>{formatNumber(student.sessions_count)}</strong>
                </span>
                <span className="ec-stat ec-tone-muted">
                  <em>{t('progress.allTime')}</em>
                  <strong>{t('class.minutesShort', { count: formatNumber(student.practice_minutes) })}</strong>
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
        <div className="ec-inline-error" role="status">
          <p>{t('class.invitationsUnavailable')}</p>
          <button className="ghost-button" type="button" onClick={() => void loadEverything(selectedGroup?.id)}>{t('auth.tryAgain')}</button>
        </div>
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
              <div className="ec-class-tabs" role="tablist" aria-label={t('nav.class')} aria-busy={loading}>
              {groups.map((group) => (
                <button
                  key={group.id}
                  type="button"
                  role="tab"
                  id={`ec-class-tab-${group.id}`}
                  aria-selected={selectedGroup?.id === group.id}
                  aria-controls="ec-selected-class-panel"
                  className={`chip-tab ${selectedGroup?.id === group.id ? 'active' : ''}`}
                  onClick={() => void selectGroup(group.id)}
                  onKeyDown={(event) => {
                    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
                    event.preventDefault();
                    const currentIndex = groups.findIndex((candidate) => candidate.id === group.id);
                    const direction = event.key === 'ArrowLeft' ? (dir === 'rtl' ? 1 : -1) : (dir === 'rtl' ? -1 : 1);
                    const nextIndex = event.key === 'Home' ? 0
                      : event.key === 'End' ? groups.length - 1
                        : (currentIndex + direction + groups.length) % groups.length;
                    const nextGroup = groups[nextIndex];
                    document.getElementById(`ec-class-tab-${nextGroup.id}`)?.focus();
                    void selectGroup(nextGroup.id);
                  }}
                >
                  {group.name}
                </button>
              ))}
            </div>
            <button className="ghost-button ec-newclass-btn" type="button" onClick={() => { setShowJoin((value) => !value); setShowCreate(false); }} aria-expanded={showJoin} aria-controls="ec-join-another-panel">
              <UserPlus size={16} />
              {t('class.joinAnother')}
            </button>
            <button className="ghost-button" type="button" onClick={() => { setShowCreate((value) => !value); setShowJoin(false); }} aria-expanded={showCreate} aria-controls="ec-new-class-panel">
              <Plus size={16} />
              {t('class.newClass')}
            </button>
          </div>

          {showJoin && (
            <div id="ec-join-another-panel">
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
            </div>
          )}

          {showCreate && (
            <div id="ec-new-class-panel">
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
            </div>
          )}

          {!selectedGroup ? (
            selectedGroupErrorId ? (
              <SectionCard title={groups.find((group) => group.id === selectedGroupErrorId)?.name ?? t('nav.class')}>
                <div className="ec-inline-error" role="status"><p>{t('class.errorLoad')}</p><button className="ghost-button" type="button" onClick={() => void selectGroup(selectedGroupErrorId)}>{t('auth.tryAgain')}</button></div>
              </SectionCard>
            ) : (
              <SectionCard title={t('class.loading')}>
                <p className="muted-copy" role="status">{t('class.loadingSelected')}</p>
              </SectionCard>
            )
          ) : (
            <div
              className="ec-print-area"
              id="ec-selected-class-panel"
              role="tabpanel"
              aria-labelledby={`ec-class-tab-${selectedGroup.id}`}
            >
              <SectionCard title={selectedGroup?.name ?? t('nav.class')} action={leaveClassAction}>
                <div className="ec-print-only ec-print-head">
                  <h2>{selectedGroup?.name ?? t('nav.class')}</h2>
                  <p>{t('class.reportDate', { date: formatDate(new Date(), { dateStyle: 'medium' }) })}</p>
                </div>

                <div className="ec-role-summary">
                  <span className="ec-badge">{viewerRoleLabel(selectedGroup.viewer_role, t)}</span>
                  {selectedViewMode === 'assistant' && <span>{t('class.readOnlyRoster')}</span>}
                </div>

                {needsSharingConsent && (
                  <div className="ec-consent-gate" role="status">
                    <div>
                      <strong>{t('class.enableSharingTitle')}</strong>
                      <p>{t('class.enableSharingBody')}</p>
                      <p className="muted-copy">{t('class.practiceDisclosure')}</p>
                    </div>
                    <button className="primary-button" type="button" onClick={enableSharing} disabled={enablingSharing} aria-busy={enablingSharing}>
                      {enablingSharing ? t('class.enablingSharing') : t('class.enableSharing')}
                    </button>
                  </div>
                )}

                {selectedViewMode === 'owner' && (
                  <>
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
                  <label className="ec-select">
                    <span>{t('class.inviteRole')}</span>
                    <select value={inviteRole} onChange={(event) => setInviteRole(event.target.value as 'student' | 'assistant')} disabled={invitingMember}>
                      <option value="student">{t('class.student')}</option>
                      <option value="assistant">{t('class.inviteRoleAssistant')}</option>
                    </select>
                    {inviteRole === 'assistant' && <small className="ec-role-help">{t('class.assistantRoleHelp')}</small>}
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
                  </>
                )}

                {selectedViewMode === 'student' && !needsSharingConsent && (
                  <div className="ec-student-progress">
                    {progressState === 'loading' && <p className="muted-copy" role="status">{t('progress.loading')}</p>}
                    {progressState === 'error' && (
                      <div className="ec-inline-error" role="status">
                        <p>{t('progress.loadFailedBody')}</p>
                        <button className="ghost-button" type="button" onClick={() => void retryResource('progress')}>{t('auth.tryAgain')}</button>
                      </div>
                    )}
                    {progressState === 'ready' && myProgress && (
                      <>
                        <div className="ec-progress-grid">
                          <article><span>{t('progress.allTime')}</span><strong>{t('class.minutesShort', { count: formatNumber(myProgress.lifetime.practice_minutes) })}</strong><small>{formatNumber(myProgress.lifetime.sessions_count)} {t('class.sessions')}</small></article>
                          <article><span>{t('class.thisWeek')}</span><strong>{t('class.minutesShort', { count: formatNumber(myProgress.current_7d.practice_minutes) })}</strong><small>{t('class.minutesDelta', { count: signedDelta(myProgress.delta.practice_minutes) })}</small></article>
                          <article><span>{t('class.lastPractice')}</span><strong>{relativeWhen(myProgress.inactivity.last_practice_at, t, formatNumber)}</strong><small>{inactivityLabel(myProgress)}</small></article>
                          <article><span>{t('class.onPitch')}</span><strong><bdi dir="ltr">{myProgress.current_7d.in_tune_percentage == null ? '—' : `${formatNumber(Math.round(myProgress.current_7d.in_tune_percentage))}%`}</bdi></strong><small>{t('class.thisWeek')}</small></article>
                        </div>
                        <div className="ec-privacy-scope">
                          <strong>{t('class.sharedDataTitle')}</strong>
                          <p>{t('class.sharedDataBody', { date: formatDate(myProgress.membership_started_at ?? new Date(), { dateStyle: 'medium' }) })}</p>
                        </div>
                        <Link className="primary-button ec-practice-now" to="/practice">{t('class.practiceNow')}</Link>
                      </>
                    )}
                  </div>
                )}

                {selectedGroup.viewer_can_view_roster && !needsSharingConsent && (
                  <>
                    {rosterState === 'loading' && <p className="muted-copy" role="status">{t('class.loadingSelected')}</p>}
                    {rosterState === 'error' && (
                      <div className="ec-inline-error" role="status">
                        <p>{t('class.rosterUnavailable')}</p>
                        <button className="ghost-button" type="button" onClick={() => void retryResource('roster')}>{t('auth.tryAgain')}</button>
                      </div>
                    )}
                    {rosterState === 'ready' && roster && roster.length > 0 && (
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
                        {selectedGroup.roster_scope === 'full' && (
                          <div className="ec-roster-tools ec-no-print" aria-label={t('progress.filter')}>
                            <label className="ec-search"><Search size={16} /><span className="sr-only">{t('class.searchRoster')}</span><input value={rosterSearch} onChange={(event) => setRosterSearch(event.target.value)} placeholder={t('class.searchRoster')} /></label>
                            <label><span>{t('class.sortBy')}</span><select value={rosterSort} onChange={(event) => setRosterSort(event.target.value as RosterSort)}><option value="name">{t('class.sortName')}</option><option value="last_practice">{t('class.sortLastPractice')}</option><option value="weekly_minutes">{t('class.sortWeeklyMinutes')}</option></select></label>
                            <label><span>{t('instrument.label')}</span><select value={rosterInstrument} onChange={(event) => setRosterInstrument(event.target.value)}><option value="all">{t('class.allInstruments')}</option>{rosterInstruments.map((id) => <option value={id} key={id}>{t(`instrument.${id}` as MessageId)}</option>)}</select></label>
                            <label><span>{t('class.lastPractice')}</span><select value={rosterInactivity} onChange={(event) => setRosterInactivity(event.target.value as RosterInactivityFilter)}><option value="all">{t('class.allActivity')}</option><option value="active_week">{t('class.thisWeek')}</option><option value="needs_attention">{t('sessionReview.nextWork')}</option></select></label>
                            <label><span>{t('class.status')}</span><select value={rosterStatus} onChange={(event) => setRosterStatus(event.target.value as 'all' | 'active' | 'invited')}><option value="all">{t('class.allStatuses')}</option><option value="active">{t('class.active')}</option><option value="invited">{t('class.invited')}</option></select></label>
                          </div>
                        )}
                        <div className="ec-roster">
                          {visibleRoster.map(renderStudentCard)}
                          {visibleRoster.length === 0 && <p className="muted-copy">{t('class.noRosterMatches')}</p>}
                        </div>
                        {showAdvanced && <p className="ec-cents-note">{t('class.centsHelp')}</p>}
                      </>
                    )}
                    {rosterState === 'ready' && roster?.length === 0 && <p className="muted-copy">{t('class.noStudents')}</p>}
                  </>
                )}
              </SectionCard>

              {(summaryState !== 'idle' || reportState !== 'idle') && (
                <>
                  <SectionCard title={t('class.sections')}>
                    {summaryState === 'loading' && <p className="muted-copy" role="status">{t('class.loadingSelected')}</p>}
                    {summaryState === 'error' && (
                      <div className="ec-inline-error" role="status"><p>{t('class.summaryUnavailable')}</p><button className="ghost-button" type="button" onClick={() => void retryResource('summary')}>{t('auth.tryAgain')}</button></div>
                    )}
                    {summaryState === 'ready' && summary && <>
                      <div className="ec-class-trend">
                        <span>{t('class.thisWeek')}</span>
                        <strong>{t('class.minutesShort', { count: formatNumber(summary.trends.current_7d.practice_minutes) })}</strong>
                        <small>{t('class.minutesDelta', { count: signedDelta(summary.trends.delta.practice_minutes) })}</small>
                      </div>
                      <div className="ec-sections">
                      {summary.sections.map((section) => {
                        const tuning = describeAverageOff(section.average_abs_cents);
                        return (
                          <article className="ec-section" key={section.instrument_id}>
                            <span className="ec-section-name">{t(`instrument.${section.instrument_id}` as MessageId)}</span>
                            <strong className={`ec-tone-${tuning.tone}`}>{t(tuning.tone === 'green' ? 'playAlong.grade.excellent' : tuning.tone === 'amber' ? 'playAlong.grade.close' : tuning.tone === 'red' ? 'playAlong.grade.off' : 'class.noPlays')}</strong>
                            <p>{t('class.sectionSummary', { sessions: formatNumber(section.session_count), minutes: formatNumber(section.practice_minutes) })}</p>
                          </article>
                        );
                      })}
                      {summary.sections.length === 0 && (
                        <p className="muted-copy">{t('class.sectionEmpty')}</p>
                      )}
                    </div></>}
                  </SectionCard>

                  {reportState === 'loading' && (
                    <SectionCard title={t('sessionReview.nextWork')}>
                      <p className="muted-copy" role="status">{t('class.loadingSelected')}</p>
                    </SectionCard>
                  )}

                  {reportState === 'error' && (
                    <SectionCard title={t('sessionReview.nextWork')}>
                      <div className="ec-inline-error" role="status"><p>{t('class.reportUnavailable')}</p><button className="ghost-button" type="button" onClick={() => void retryResource('report')}>{t('auth.tryAgain')}</button></div>
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

                  {reportState === 'ready' && report && report.top_problem_notes.length > 0 && (
                    <SectionCard title={t('class.notesFocus')}>
                      <NoteStatsTable rows={report.top_problem_notes} />
                    </SectionCard>
                  )}
                </>
              )}
            </div>
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
