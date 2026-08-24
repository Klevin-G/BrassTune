import { expect, test, type Page, type Route } from 'playwright/test';

type Group = {
  id: number;
  name: string;
  join_code?: string | null;
  director_user_id?: number | null;
  viewer_role: 'owner' | 'assistant' | 'student' | 'admin_observer';
  viewer_can_leave: boolean;
  viewer_can_manage: boolean;
  viewer_can_view_roster: boolean;
  viewer_can_view_class_analytics: boolean;
  viewer_has_aggregate_sharing_consent: boolean;
  roster_scope: 'full' | 'active_redacted' | 'self';
};

type Invitation = {
  member_id: number;
  group_id: number;
  group_name: string;
  instrument_id: string;
  role_in_group: string;
  invited_at: string | null;
  director_name: string | null;
};

type RosterStudent = {
  roster_row_id: string;
  member_id: number;
  user_id: number;
  username: string;
  display_name: string;
  instrument_id: string;
  status: string;
  role_in_group: string;
  sessions_count: number;
  practice_minutes: number;
  average_abs_cents: number | null;
  in_tune_percentage: number | null;
  last_practice_at: string | null;
  last_active_at: string | null;
  lifetime: PracticeWindow;
  current_7d: PracticeWindow;
  previous_7d: PracticeWindow;
  delta: Omit<PracticeWindow, 'last_practice_at'>;
  inactivity: {
    state: 'active_today' | 'active_this_week' | 'inactive_7d' | 'no_practice_since_joining';
    days_since_last_practice: number | null;
    last_practice_at: string | null;
  };
};

type PracticeWindow = {
  sessions_count: number;
  practice_minutes: number;
  average_abs_cents: number | null;
  in_tune_percentage: number | null;
  last_practice_at: string | null;
};

type FixtureOptions = {
  groupDelaysMs?: Record<number, number>;
  mutationDelayMs?: number;
  invitations?: Invitation[];
  initialGroups?: Group[];
  initialRoster?: RosterStudent[];
  onboardingCompletedAt?: string | null;
  onboardingUpdateFailures?: number;
  onboardingUpdateDelayMs?: number;
  initialProfileFailures?: number;
  holdProfileUntilReleased?: boolean;
};

const hornProfile = {
  id: 'horn',
  display_name: 'French Horn in F',
  transposition_semitones: 7,
  min_frequency_hz: 80,
  max_frequency_hz: 1200,
  preferred_note_spellings: ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'],
  typical_range_written: 'F3-C6',
  common_tuning_tendencies: ['Hand position affects resonance and intonation.'],
  recommendation_templates: { sharp: [], flat: [], unstable: [] },
  future_swift_notes: 'Keep transposition and horn-specific coaching in plain data.',
};

const delay = (milliseconds: number) => new Promise((resolve) => setTimeout(resolve, milliseconds));

const practiceAggregateScope = {
  code: 'cloud_practice_sessions_since_membership_v1',
  source: 'cloud_practice_sessions',
  window: 'membership_active_since',
  excludes: ['reflections', 'audio', 'session_detail'],
};

const emptyPracticeWindow = (): PracticeWindow => ({
  sessions_count: 0,
  practice_minutes: 0,
  average_abs_cents: null,
  in_tune_percentage: null,
  last_practice_at: null,
});

function classCapabilities(group: Group) {
  return {
    viewer_role: group.viewer_role,
    viewer_can_leave: group.viewer_can_leave,
    viewer_can_manage: group.viewer_can_manage,
    viewer_can_view_roster: group.viewer_can_view_roster,
    viewer_can_view_class_analytics: group.viewer_can_view_class_analytics,
    viewer_has_aggregate_sharing_consent: group.viewer_has_aggregate_sharing_consent,
    roster_scope: group.roster_scope,
  };
}

const fakeAuthModule = `
const session = { access_token: 'signed-in-e2e-token', user: { id: 'class-user' } };
export const supabaseConfigured = true;
export const authProviders = { google: false, apple: false };
export const supabase = {
  auth: {
    get storageKey() {
      if (localStorage.getItem('brasstune.e2eAuthStorageFailure') === 'true') {
        throw new Error('storage unavailable');
      }
      return 'sb-brasstune-e2e-auth-token';
    },
    getSession: async () => ({ data: { session } }),
    onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
    signOut: async () => {
      const calls = Number(localStorage.getItem('brasstune.e2eSignOutCalls') || '0') + 1;
      localStorage.setItem('brasstune.e2eSignOutCalls', String(calls));
      localStorage.setItem('brasstune.e2eSignOutStarted', 'true');
      if (localStorage.getItem('brasstune.e2eSignOutHeld') === 'true') {
        await new Promise((resolve) => {
          const gate = window.setInterval(() => {
            if (localStorage.getItem('brasstune.e2eSignOutRelease') !== 'true') return;
            window.clearInterval(gate);
            resolve(undefined);
          }, 10);
        });
      }
      if (localStorage.getItem('brasstune.e2eSignOutFailure') === 'true') {
        return { error: new Error('network request failed') };
      }
      localStorage.setItem('brasstune.e2eSignOutFinished', 'true');
      return { error: null };
    },
    signInWithPassword: async () => ({ data: { session }, error: null }),
    signUp: async () => ({ data: { session }, error: null }),
  },
};
`;

async function installSignedInClassFixture(page: Page, options: FixtureOptions = {}) {
  let profileFailureReleased = false;
  let onboardingCompletedAt = options.onboardingCompletedAt === undefined
    ? '2026-07-16T12:00:00Z'
    : options.onboardingCompletedAt;
  let groups: Group[] = options.initialGroups ? [...options.initialGroups] : [
    { id: 1, name: 'Concert Band', director_user_id: 12, viewer_role: 'student', viewer_can_leave: true, viewer_can_manage: false, viewer_can_view_roster: false, viewer_can_view_class_analytics: false, viewer_has_aggregate_sharing_consent: true, roster_scope: 'self' },
    { id: 2, name: 'Jazz Band', viewer_role: 'assistant', viewer_can_leave: true, viewer_can_manage: false, viewer_can_view_roster: true, viewer_can_view_class_analytics: true, viewer_has_aggregate_sharing_consent: true, roster_scope: 'active_redacted' },
    { id: 3, name: 'Student-led Brass', join_code: null, viewer_role: 'owner', viewer_can_leave: false, viewer_can_manage: true, viewer_can_view_roster: true, viewer_can_view_class_analytics: true, viewer_has_aggregate_sharing_consent: false, roster_scope: 'full' },
    { id: 4, name: 'Legacy-owned Brass', join_code: 'LEGACY99', director_user_id: 99, viewer_role: 'owner', viewer_can_leave: false, viewer_can_manage: true, viewer_can_view_roster: true, viewer_can_view_class_analytics: true, viewer_has_aggregate_sharing_consent: false, roster_scope: 'full' },
  ];
  let invitations = [...(options.invitations ?? [])];
  let roster = [...(options.initialRoster ?? [])];
  const counters = {
    creates: 0,
    memberInvites: 0,
    sharingEnables: 0,
    accepts: 0,
    declines: 0,
    joins: 0,
    leaves: 0,
    removes: 0,
    onboardingUpdates: 0,
    profileLoads: 0,
    releaseProfileFailure: () => {
      profileFailureReleased = true;
    },
    joinPayload: null as { code?: string; instrument_id?: string; sharing_consent?: { scope_code?: string; acknowledged?: boolean } } | null,
    memberInvitePayload: null as { username?: string; instrument_id?: string; role_in_group?: string } | null,
    sharingConsentPayload: null as { sharing_consent?: { scope_code?: string; acknowledged?: boolean } } | null,
  };

  await page.route('**/src/lib/supabase.ts*', async (route) => {
    await route.fulfill({ status: 200, contentType: 'application/javascript', body: fakeAuthModule });
  });

  await page.route(/^https?:\/\/[^/]+\/api\//, async (route: Route) => {
    const request = route.request();
    const url = new URL(request.url());
    const path = url.pathname;
    const respond = (body: unknown, status = 200) => route.fulfill({
      status,
      contentType: 'application/json',
      body: JSON.stringify(body),
    });

    if (path === '/api/instruments') return respond([hornProfile]);
    if (path === '/api/users/current') {
      counters.profileLoads += 1;
      if (
        (options.holdProfileUntilReleased && !profileFailureReleased) ||
        counters.profileLoads <= (options.initialProfileFailures ?? 0)
      ) {
        return respond({ detail: 'Temporary profile failure.' }, 503);
      }
      return respond({
        id: 99,
        supabase_user_id: 'class-user',
        username: 'student99',
        display_name: 'Class Student',
        email: 'student@example.test',
        role: 'director',
        primary_instrument_id: 'horn',
        onboarding_completed_at: onboardingCompletedAt,
      });
    }
    if (path === '/api/users/me' && request.method() === 'PATCH') {
      counters.onboardingUpdates += 1;
      if (options.onboardingUpdateDelayMs) await delay(options.onboardingUpdateDelayMs);
      if (counters.onboardingUpdates <= (options.onboardingUpdateFailures ?? 0)) {
        return respond({ detail: 'Temporary onboarding persistence failure.' }, 503);
      }
      onboardingCompletedAt = '2026-07-16T12:30:00Z';
      return respond({ onboarding_completed_at: onboardingCompletedAt });
    }
    if (path === '/api/ensemble/invitations' && request.method() === 'GET') return respond({ invitations });
    if (path === '/api/ensemble/groups' && request.method() === 'GET') return respond(groups);

    if (path === '/api/ensemble/join' && request.method() === 'POST') {
      counters.joins += 1;
      const payload = request.postDataJSON() as { code?: string; instrument_id?: string };
      counters.joinPayload = payload;
      if (options.mutationDelayMs) await delay(options.mutationDelayMs);
      if (payload.code !== 'CHAMBER7') return respond({ detail: 'Invalid class code.' }, 404);
      const group: Group = {
        id: Math.max(...groups.map((candidate) => candidate.id), 0) + 1,
        name: 'Chamber Winds',
        director_user_id: 12,
        viewer_role: 'student',
        viewer_can_leave: true,
        viewer_can_manage: false,
        viewer_can_view_roster: false,
        viewer_can_view_class_analytics: false,
        viewer_has_aggregate_sharing_consent: true,
        roster_scope: 'self',
      };
      groups = [...groups, group];
      return respond({ joined: true, group_id: group.id, group_name: group.name });
    }

    if (path === '/api/ensemble/groups' && request.method() === 'POST') {
      counters.creates += 1;
      if (options.mutationDelayMs) await delay(options.mutationDelayMs);
      const payload = request.postDataJSON() as { name?: string };
      const group: Group = {
        id: Math.max(...groups.map((candidate) => candidate.id), 0) + 1,
        name: payload.name ?? 'New class',
        join_code: 'NEWCLASS',
        director_user_id: 99,
        viewer_role: 'owner',
        viewer_can_leave: false,
        viewer_can_manage: true,
        viewer_can_view_roster: true,
        viewer_can_view_class_analytics: true,
        viewer_has_aggregate_sharing_consent: false,
        roster_scope: 'full',
      };
      groups = [...groups, group];
      return respond(group);
    }

    const invitationResponseMatch = path.match(/^\/api\/ensemble\/invitations\/(\d+)\/(accept|decline)$/);
    if (invitationResponseMatch && request.method() === 'POST') {
      const memberID = Number(invitationResponseMatch[1]);
      const action = invitationResponseMatch[2];
      if (action === 'accept') counters.accepts += 1;
      else counters.declines += 1;
      if (options.mutationDelayMs) await delay(options.mutationDelayMs);
      const invitation = invitations.find((candidate) => candidate.member_id === memberID);
      invitations = invitations.filter((candidate) => candidate.member_id !== memberID);
      return respond(action === 'accept'
        ? { accepted: true, group_id: invitation?.group_id ?? 1 }
        : { declined: true });
    }

    const memberInviteMatch = path.match(/^\/api\/ensemble\/groups\/(\d+)\/members\/by-username$/);
    if (memberInviteMatch && request.method() === 'POST') {
      counters.memberInvites += 1;
      counters.memberInvitePayload = request.postDataJSON() as { username?: string; instrument_id?: string; role_in_group?: string };
      if (options.mutationDelayMs) await delay(options.mutationDelayMs);
      return respond({ id: 901, group_id: Number(memberInviteMatch[1]), status: 'invited' });
    }

    const rotateMatch = path.match(/^\/api\/ensemble\/groups\/(\d+)\/join-code\/rotate$/);
    if (rotateMatch && request.method() === 'POST') {
      const groupID = Number(rotateMatch[1]);
      groups = groups.map((group) => group.id === groupID ? { ...group, join_code: 'ABCD2345' } : group);
      return respond({ group_id: groupID, join_code: 'ABCD2345' });
    }

    const leaveMatch = path.match(/^\/api\/ensemble\/groups\/(\d+)\/membership$/);
    if (leaveMatch && request.method() === 'DELETE') {
      counters.leaves += 1;
      const groupID = Number(leaveMatch[1]);
      if (options.mutationDelayMs) await delay(options.mutationDelayMs);
      groups = groups.filter((group) => group.id !== groupID);
      return respond({ left: true, group_id: groupID });
    }

    const removeMatch = path.match(/^\/api\/ensemble\/groups\/(\d+)\/members\/(\d+)$/);
    if (removeMatch && request.method() === 'DELETE') {
      counters.removes += 1;
      const memberID = Number(removeMatch[2]);
      if (options.mutationDelayMs) await delay(options.mutationDelayMs);
      roster = roster.filter((member) => member.member_id !== memberID);
      return respond({ removed: true });
    }

    const sharingConsentMatch = path.match(/^\/api\/ensemble\/groups\/(\d+)\/sharing-consent$/);
    if (sharingConsentMatch && request.method() === 'POST') {
      counters.sharingEnables += 1;
      counters.sharingConsentPayload = request.postDataJSON() as { sharing_consent?: { scope_code?: string; acknowledged?: boolean } };
      const groupID = Number(sharingConsentMatch[1]);
      groups = groups.map((group) => group.id === groupID
        ? { ...group, viewer_has_aggregate_sharing_consent: true }
        : group);
      return respond({
        group_id: groupID,
        viewer_has_aggregate_sharing_consent: true,
        aggregate_sharing_consented_at: '2026-08-24T12:00:00Z',
        aggregate_sharing_scope_code: 'cloud_practice_sessions_since_membership_v1',
      });
    }

    const groupMatch = path.match(/^\/api\/ensemble\/groups\/(\d+)$/);
    if (groupMatch && request.method() === 'GET') {
      const groupID = Number(groupMatch[1]);
      const groupDelay = options.groupDelaysMs?.[groupID] ?? 0;
      if (groupDelay) await delay(groupDelay);
      const group = groups.find((candidate) => candidate.id === groupID);
      if (!group) return respond({ detail: 'Group not found' }, 404);
      return respond({
        ...group,
        members: group.viewer_can_manage ? [] : [{
          id: group.id * 10,
          group_id: group.id,
          instrument_id: 'horn',
          role_in_group: group.viewer_role === 'assistant' ? 'assistant' : 'student',
          status: 'active',
          display_name: 'You',
          is_current_user: true,
        }],
      });
    }

    const rosterMatch = path.match(/^\/api\/ensemble\/groups\/(\d+)\/roster$/);
    if (rosterMatch) {
      const group = groups.find((candidate) => candidate.id === Number(rosterMatch[1]));
      if (!group) return respond({ detail: 'Group not found' }, 404);
      const students = group.roster_scope === 'active_redacted'
        ? roster.filter((student) => student.status === 'active').map(({ member_id: _memberId, user_id: _userId, username: _username, ...student }) => student)
        : roster;
      return respond({
        group_id: group.id,
        practice_aggregate_scope: practiceAggregateScope,
        students,
        ...classCapabilities(group),
      });
    }
    const summaryMatch = path.match(/^\/api\/ensemble\/groups\/(\d+)\/summary$/);
    if (summaryMatch) {
      const group = groups.find((candidate) => candidate.id === Number(summaryMatch[1]));
      if (!group) return respond({ detail: 'Group not found' }, 404);
      const current = emptyPracticeWindow();
      return respond({
        group_id: group.id,
        session_count: 0,
        sections: [],
        overall: { instrument_id: 'all', session_count: 0, practice_minutes: 0, average_abs_cents: null, in_tune_percentage: null, top_problem_notes: [] },
        trends: { current_7d: current, previous_7d: current, delta: { sessions_count: 0, practice_minutes: 0, average_abs_cents: null, in_tune_percentage: null }, generated_at: '2026-08-24T12:00:00Z' },
        practice_aggregate_scope: practiceAggregateScope,
        ...classCapabilities(group),
      });
    }
    const reportMatch = path.match(/^\/api\/ensemble\/groups\/(\d+)\/report$/);
    if (reportMatch) {
      const group = groups.find((candidate) => candidate.id === Number(reportMatch[1]));
      if (!group) return respond({ detail: 'Group not found' }, 404);
      return respond({
        group_id: group.id,
        date_range: 'all available ensemble sessions',
        instrument_section: 'all brass',
        top_problem_notes: [],
        average_tuning_error: null,
        recommended_rehearsal_focus: '',
        suggested_long_tone_sequence: [],
        sections: [],
        practice_aggregate_scope: practiceAggregateScope,
        ...classCapabilities(group),
      });
    }
    const progressMatch = path.match(/^\/api\/ensemble\/groups\/(\d+)\/my-progress$/);
    if (progressMatch) {
      const group = groups.find((candidate) => candidate.id === Number(progressMatch[1]));
      if (!group) return respond({ detail: 'Group not found' }, 404);
      const lifetime = emptyPracticeWindow();
      return respond({
        group_id: group.id,
        group_name: group.name,
        instrument_id: 'horn',
        role_in_group: 'student',
        membership_started_at: '2026-08-01T12:00:00Z',
        practice_aggregate_scope: practiceAggregateScope,
        lifetime,
        current_7d: lifetime,
        previous_7d: lifetime,
        delta: { sessions_count: 0, practice_minutes: 0, average_abs_cents: null, in_tune_percentage: null },
        inactivity: { state: 'no_practice_since_joining', days_since_last_practice: null, last_practice_at: null },
        generated_at: '2026-08-24T12:00:00Z',
      });
    }
    return respond({ detail: 'Unexpected class fixture request' }, 500);
  });

  await page.addInitScript(() => {
    localStorage.setItem('brasstune.onboardingComplete', 'true');
    localStorage.setItem('brasstune.guestOnboardingComplete', 'true');
    localStorage.setItem('brasstune.instrument', 'horn');
    localStorage.setItem('brasstune.referencePitch', '442');
    localStorage.setItem('brasstune.guestSessions.v1', JSON.stringify([{ id: -901, name: 'Local warmup' }]));
  });

  return counters;
}

const switchingAuthModule = `
let session = { access_token: 'token-a', user: { id: 'account-a' } };
const listeners = new Set();
globalThis.__brasstuneSwitchAccount = (userId) => {
  session = { access_token: userId === 'account-b' ? 'token-b' : 'token-c', user: { id: userId } };
  listeners.forEach((listener) => listener('SIGNED_IN', session));
};
export const supabaseConfigured = true;
export const authProviders = { google: false, apple: false };
export const supabase = {
  auth: {
    getSession: async () => ({ data: { session } }),
    onAuthStateChange: (listener) => {
      listeners.add(listener);
      return { data: { subscription: { unsubscribe() { listeners.delete(listener); } } } };
    },
    signOut: async () => ({ error: null }),
    signInWithPassword: async () => ({ data: { session }, error: null }),
    signUp: async () => ({ data: { session }, error: null }),
  },
};
`;

async function installAccountSwitchFixture(
  page: Page,
  options: { failAccountBProfile?: boolean; delayAccountAJoin?: boolean } = {},
) {
  let releaseAccountAJoin: () => void = () => undefined;
  const accountAJoinGate = new Promise<void>((resolve) => {
    releaseAccountAJoin = resolve;
  });
  const counters = {
    failedProfileLoads: 0,
    failedAccountGroupLoads: 0,
    accountAJoins: 0,
    groupLoads: { 'token-a': 0, 'token-b': 0, 'token-c': 0 } as Record<string, number>,
    releaseAccountAJoin: () => releaseAccountAJoin(),
  };

  await page.route('**/src/lib/supabase.ts*', async (route) => {
    await route.fulfill({ status: 200, contentType: 'application/javascript', body: switchingAuthModule });
  });

  await page.route(/^https?:\/\/[^/]+\/api\//, async (route: Route) => {
    const request = route.request();
    const path = new URL(request.url()).pathname;
    const token = request.headers().authorization?.replace(/^Bearer\s+/i, '') ?? '';
    const respond = (body: unknown, status = 200) => route.fulfill({
      status,
      contentType: 'application/json',
      body: JSON.stringify(body),
    });

    if (path === '/api/instruments') return respond([hornProfile]);
    if (path === '/api/users/current') {
      if (token === 'token-b' && options.failAccountBProfile !== false) {
        counters.failedProfileLoads += 1;
        return respond({ detail: 'Temporary profile failure.' }, 503);
      }
      const isAccountB = token === 'token-b';
      const isAccountC = token === 'token-c';
      return respond({
        id: isAccountC ? 303 : isAccountB ? 202 : 101,
        supabase_user_id: isAccountC ? 'account-c' : isAccountB ? 'account-b' : 'account-a',
        username: isAccountC ? 'account-c' : isAccountB ? 'account-b' : 'account-a',
        display_name: isAccountC ? 'Account C' : isAccountB ? 'Account B' : 'Account A',
        email: isAccountC ? 'c@example.test' : isAccountB ? 'b@example.test' : 'a@example.test',
        role: 'student',
        primary_instrument_id: 'trumpet',
        onboarding_completed_at: '2026-07-16T12:00:00Z',
      });
    }
    if (path === '/api/ensemble/invitations') return respond({ invitations: [] });
    if (path === '/api/ensemble/join' && request.method() === 'POST') {
      if (token === 'token-a') {
        counters.accountAJoins += 1;
        if (options.delayAccountAJoin) await accountAJoinGate;
        return respond({ joined: true, group_id: 111, group_name: 'Account A Late Class' });
      }
      return respond({ joined: true, group_id: 222, group_name: 'Account B Joined Class' });
    }
    if (path === '/api/ensemble/groups') {
      if (token === 'token-b') counters.failedAccountGroupLoads += 1;
      counters.groupLoads[token] = (counters.groupLoads[token] ?? 0) + 1;
      const isAccountB = token === 'token-b';
      const isAccountC = token === 'token-c';
      return respond([{
        id: isAccountC ? 303 : isAccountB ? 202 : 101,
        name: isAccountC ? 'Account C Class' : isAccountB ? 'Account B Class' : 'Account A Class',
        viewer_role: 'student',
        viewer_can_leave: true,
        viewer_can_manage: false,
        viewer_can_view_roster: false,
        viewer_can_view_class_analytics: false,
        viewer_has_aggregate_sharing_consent: true,
        roster_scope: 'self',
      }]);
    }
    const groupMatch = path.match(/^\/api\/ensemble\/groups\/(\d+)$/);
    if (groupMatch) {
      const isAccountB = token === 'token-b';
      const isAccountC = token === 'token-c';
      return respond({
        id: Number(groupMatch[1]),
        name: isAccountC ? 'Account C Class' : isAccountB ? 'Account B Class' : 'Account A Class',
        viewer_role: 'student',
        viewer_can_leave: true,
        viewer_can_manage: false,
        viewer_can_view_roster: false,
        viewer_can_view_class_analytics: false,
        viewer_has_aggregate_sharing_consent: true,
        roster_scope: 'self',
        members: [],
      });
    }
    const progressMatch = path.match(/^\/api\/ensemble\/groups\/(\d+)\/my-progress$/);
    if (progressMatch) {
      const isAccountB = token === 'token-b';
      const isAccountC = token === 'token-c';
      const lifetime = emptyPracticeWindow();
      return respond({
        group_id: Number(progressMatch[1]),
        group_name: isAccountC ? 'Account C Class' : isAccountB ? 'Account B Class' : 'Account A Class',
        instrument_id: 'trumpet',
        role_in_group: 'student',
        membership_started_at: '2026-08-01T12:00:00Z',
        practice_aggregate_scope: practiceAggregateScope,
        lifetime,
        current_7d: lifetime,
        previous_7d: lifetime,
        delta: { sessions_count: 0, practice_minutes: 0, average_abs_cents: null, in_tune_percentage: null },
        inactivity: { state: 'no_practice_since_joining', days_since_last_practice: null, last_practice_at: null },
      });
    }
    return respond({ detail: 'Unexpected account-switch fixture request.' }, 500);
  });

  await page.addInitScript(() => {
    localStorage.setItem('brasstune.onboardingComplete', 'true');
    localStorage.setItem('brasstune.guestOnboardingComplete', 'true');
    localStorage.setItem('brasstune.instrument', 'trumpet');
  });

  return counters;
}

test('a restored session profile failure keeps recovery controls visible and retries without crossing practice owners', async ({ page }) => {
  const counters = await installSignedInClassFixture(page, { holdProfileUntilReleased: true });
  await page.addInitScript(() => {
    const library = (label: string) => JSON.stringify({
      version: 1,
      customExercises: [],
      metronomePresets: [],
      favorites: [],
      recents: [],
      reflections: [],
      warmup: { elapsedSeconds: 0, stepIndex: 0, updatedAt: '2026-07-23T00:00:00.000Z' },
      weeklyGoal: { week: '2026-07-20', targetMinutes: label === 'account' ? 91 : 37, completedMinutes: 0, targetSessions: 3, completedSessions: 0 },
    });
    localStorage.setItem('brasstune.practiceLibrary.v1.guest', library('guest'));
    localStorage.setItem('brasstune.practiceLibrary.v1.account%3A99', library('account'));
  });

  await page.goto('/practice');
  await expect(page.getByRole('heading', { name: 'We could not finish restoring your account' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Try again' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Sign out' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Continue as guest' })).toBeVisible();
  await expect(page.getByText('Live mic', { exact: true })).toHaveCount(0);
  const beforeRetry = await page.evaluate(() => ({
    guest: localStorage.getItem('brasstune.practiceLibrary.v1.guest'),
    account: localStorage.getItem('brasstune.practiceLibrary.v1.account%3A99'),
  }));

  counters.releaseProfileFailure();
  await page.getByRole('button', { name: 'Try again' }).click();
  await expect(page.getByText('Live mic', { exact: true })).toBeVisible();
  await expect(page.getByLabel('Goal in minutes')).toHaveValue('91');
  expect(counters.profileLoads).toBeGreaterThan(1);
  const afterRetry = await page.evaluate(() => ({
    guest: localStorage.getItem('brasstune.practiceLibrary.v1.guest'),
    account: localStorage.getItem('brasstune.practiceLibrary.v1.account%3A99'),
  }));
  expect(afterRetry.guest).toBe(beforeRetry.guest);
  expect(JSON.parse(afterRetry.guest ?? '{}').weeklyGoal.targetMinutes).toBe(37);
  expect(JSON.parse(afterRetry.account ?? '{}').weeklyGoal.targetMinutes).toBe(91);
});

test('unresolved identity recovery awaits one guest transition and keeps failures visible', async ({ page }) => {
  await installSignedInClassFixture(page, { holdProfileUntilReleased: true });
  await page.addInitScript(() => {
    localStorage.setItem('brasstune.e2eSignOutHeld', 'true');
    localStorage.setItem('brasstune.e2eSignOutFailure', 'true');
    localStorage.setItem('brasstune.e2eAuthStorageFailure', 'true');
  });

  await page.goto('/practice');
  const recoveryHeading = page.getByRole('heading', { name: 'We could not finish restoring your account' });
  const guestButton = page.getByRole('button', { name: 'Continue as guest' });
  await expect(recoveryHeading).toBeVisible();

  await guestButton.click();
  await expect(guestButton).toBeDisabled();
  await expect.poll(() => page.evaluate(() => localStorage.getItem('brasstune.e2eSignOutStarted'))).toBe('true');
  await expect(recoveryHeading).toBeVisible();
  await expect(page.getByText('Live mic', { exact: true })).toHaveCount(0);
  await page.evaluate(() => localStorage.setItem('brasstune.e2eSignOutRelease', 'true'));
  await expect(page.getByRole('alert')).toHaveText('Sign-out could not complete. Try again.');
  await expect(guestButton).toBeEnabled();
  await expect.poll(() => page.evaluate(() => localStorage.getItem('brasstune.e2eSignOutCalls'))).toBe('1');
  await expect.poll(() => page.evaluate(() => sessionStorage.getItem('brasstune.guestAccess'))).toBeNull();

  await page.evaluate(() => {
    localStorage.removeItem('brasstune.e2eSignOutFailure');
    localStorage.removeItem('brasstune.e2eAuthStorageFailure');
    localStorage.removeItem('brasstune.e2eSignOutHeld');
  });
  await guestButton.click();
  await expect(page.getByText('Live mic', { exact: true })).toBeVisible();
  await expect.poll(() => page.evaluate(() => localStorage.getItem('brasstune.e2eSignOutCalls'))).toBe('2');
  await expect.poll(() => page.evaluate(() => localStorage.getItem('brasstune.e2eSignOutFinished'))).toBe('true');
  await expect.poll(() => page.evaluate(() => sessionStorage.getItem('brasstune.guestAccess'))).toBe('true');
  await expect(recoveryHeading).toHaveCount(0);
});

test('switching Supabase users clears the prior profile and class data before reloading', async ({ page }) => {
  const counters = await installAccountSwitchFixture(page);
  await page.goto('/ensemble');
  await expect(page.getByRole('heading', { name: 'Account A Class' })).toBeVisible();

  await page.evaluate(() => {
    (globalThis as typeof globalThis & { __brasstuneSwitchAccount: (userId: string) => void })
      .__brasstuneSwitchAccount('account-b');
  });
  await expect.poll(() => counters.failedProfileLoads).toBeGreaterThan(0);
  await expect(page.getByRole('heading', { name: 'Account A Class' })).toHaveCount(0);
  await expect(page.getByText('Account A', { exact: true })).toHaveCount(0);
  expect(counters.failedAccountGroupLoads).toBe(0);

  await page.evaluate(() => {
    (globalThis as typeof globalThis & { __brasstuneSwitchAccount: (userId: string) => void })
      .__brasstuneSwitchAccount('account-c');
  });
  await expect(page.getByRole('heading', { name: 'Account C Class' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Account A Class' })).toHaveCount(0);
});

test('a delayed join from account A cannot reload or label account B', async ({ page }) => {
  const counters = await installAccountSwitchFixture(page, {
    failAccountBProfile: false,
    delayAccountAJoin: true,
  });
  await page.goto('/ensemble');
  await expect(page.getByRole('heading', { name: 'Account A Class' })).toBeVisible();

  await page.getByRole('button', { name: 'Join another class' }).click();
  await page.getByLabel('Class code').fill('late-a1');
  await page.getByRole('button', { name: 'Join', exact: true }).click();
  await expect.poll(() => counters.accountAJoins).toBe(1);

  await page.evaluate(() => {
    (globalThis as typeof globalThis & { __brasstuneSwitchAccount: (userId: string) => void })
      .__brasstuneSwitchAccount('account-b');
  });
  await expect(page.getByRole('heading', { name: 'Account B Class' })).toBeVisible();
  await expect(page.getByLabel('Class code')).toHaveCount(0);
  const accountBLoadsBeforeRelease = counters.groupLoads['token-b'];

  const delayedJoinResponse = page.waitForResponse((response) => (
    new URL(response.url()).pathname === '/api/ensemble/join'
  ));
  counters.releaseAccountAJoin();
  await delayedJoinResponse;
  await page.waitForTimeout(150);

  await expect(page.getByRole('heading', { name: 'Account B Class' })).toBeVisible();
  await expect(page.getByText(/Account A Late Class/)).toHaveCount(0);
  await expect(page.getByText(/You joined/)).toHaveCount(0);
  expect(counters.groupLoads['token-b']).toBe(accountBLoadsBeforeRelease);
});

test('a new signed-in account completes the five-step tour and retries persistence', async ({ page }) => {
  const counters = await installSignedInClassFixture(page, {
    onboardingCompletedAt: null,
    onboardingUpdateFailures: 1,
    // Keep the save pending while each browser verifies the no-enabled-control focus trap.
    onboardingUpdateDelayMs: 3_000,
  });
  await page.goto('/practice');

  const dialog = page.getByRole('dialog');
  await expect(dialog.getByRole('heading', { name: 'Choose your instrument' })).toBeVisible();
  await expect(dialog.getByText('Using an account')).toBeVisible();
  await expect(dialog.getByText('App tour · Step 1 of 5')).toBeVisible();
  await expect(dialog.getByRole('button', { name: 'Next' })).toBeVisible();
  await expect(dialog.getByRole('button', { name: 'Back' })).toHaveCount(0);
  await dialog.getByRole('combobox').selectOption('horn');
  for (let index = 0; index < 4; index += 1) {
    await dialog.getByRole('button', { name: 'Next' }).click();
  }
  await expect(dialog.getByText('App tour · Step 5 of 5')).toBeVisible();
  await dialog.getByRole('button', { name: 'Open the tuner' }).click();
  await expect(dialog.getByRole('button', { name: 'Saving tour…' })).toBeDisabled();
  await expect(dialog).toBeFocused();
  await page.keyboard.press('Escape');
  await page.keyboard.press('Tab');
  await expect(dialog).toBeVisible();
  await expect.poll(() => page.evaluate(() => Boolean(document.activeElement?.closest('[role="dialog"]')))).toBe(true);
  await expect(dialog.getByRole('alert')).toContainText(/couldn’t save/i);
  await expect(dialog).toBeVisible();
  await dialog.getByRole('button', { name: 'Try saving again' }).click();
  await expect(dialog).toBeHidden();
  await expect.poll(() => counters.onboardingUpdates).toBe(2);

  await page.reload();
  await expect(page.getByRole('dialog')).toHaveCount(0);
  await expect(page.getByText(/Live mic/i)).toBeVisible();
});

test('class UI stays stable across switching and leaving one of several classes', async ({ page }) => {
  await installSignedInClassFixture(page);
  await page.goto('/ensemble');

  const joinAnother = page.getByRole('button', { name: 'Join another class' });
  await expect(joinAnother).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Join another class' })).toHaveCount(0);
  await joinAnother.click();
  await expect(page.getByRole('heading', { name: 'Join another class' })).toBeVisible();
  await joinAnother.click();
  await expect(page.getByRole('heading', { name: 'Join another class' })).toHaveCount(0);
  await expect(page.getByRole('tab', { name: 'Concert Band' })).toBeVisible();
  await expect(page.getByRole('tab', { name: 'Jazz Band' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Leave class' })).toBeVisible();

  await page.getByRole('tab', { name: 'Jazz Band' }).click();
  await expect(page.getByRole('heading', { name: 'Jazz Band' })).toBeVisible();

  const leaveTrigger = page.getByRole('button', { name: 'Leave class' });
  await leaveTrigger.click();
  let dialog = page.getByRole('dialog', { name: 'Leave Jazz Band?' });
  await expect(dialog).toBeVisible();
  await dialog.getByRole('button', { name: 'Cancel' }).click();
  await expect(dialog).toBeHidden();
  await expect(leaveTrigger).toBeFocused();

  await leaveTrigger.click();
  dialog = page.getByRole('dialog', { name: 'Leave Jazz Band?' });
  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();

  await leaveTrigger.click();
  dialog = page.getByRole('dialog', { name: 'Leave Jazz Band?' });
  await dialog.getByRole('button', { name: 'Leave class' }).click();
  await expect(page.getByText(/You left.*Jazz Band/)).toBeVisible();
  await expect(page.getByRole('tab', { name: 'Jazz Band' })).toHaveCount(0);
  await expect(page.getByRole('tab', { name: 'Concert Band' })).toBeVisible();
  await expect(joinAnother).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Join another class' })).toHaveCount(0);

  await page.getByRole('tab', { name: 'Student-led Brass' }).click();
  await expect(page.getByText('Unavailable', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Copy code' })).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Share link' })).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Leave class' })).toHaveCount(0);
  await page.getByRole('button', { name: 'Create code' }).click();
  await expect(page.getByText('ABCD2345', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Rotate code' })).toBeVisible();

  await page.getByRole('tab', { name: 'Legacy-owned Brass' }).click();
  await expect(page.getByText('LEGACY99', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Leave class' })).toHaveCount(0);

  const preservedState = await page.evaluate(() => ({
    instrument: localStorage.getItem('brasstune.instrument'),
    referencePitch: localStorage.getItem('brasstune.referencePitch'),
    guestSessions: localStorage.getItem('brasstune.guestSessions.v1'),
  }));
  expect(preservedState).toEqual({
    instrument: 'horn',
    referencePitch: '442',
    guestSessions: JSON.stringify([{ id: -901, name: 'Local warmup' }]),
  });
});

test('the latest class selection wins when detail responses arrive out of order', async ({ page }) => {
  await installSignedInClassFixture(page, { groupDelaysMs: { 1: 10, 2: 250 } });
  await page.goto('/ensemble');
  await expect(page.getByRole('heading', { name: 'Concert Band' })).toBeVisible();

  const concertTab = page.getByRole('tab', { name: 'Concert Band' });
  const jazzTab = page.getByRole('tab', { name: 'Jazz Band' });
  await jazzTab.click();
  await concertTab.click();

  await expect(page.getByRole('heading', { name: 'Concert Band' })).toBeVisible();
  await page.waitForTimeout(300);
  await expect(page.getByRole('heading', { name: 'Concert Band' })).toBeVisible();
  await expect(concertTab).toHaveClass(/active/);
  await expect(jazzTab).not.toHaveClass(/active/);
});

test('joins a second class and keeps prior memberships available', async ({ page }) => {
  // Keep the mocked mutation pending long enough for every browser engine to
  // render and expose the disabled busy state before the response resolves.
  const counters = await installSignedInClassFixture(page, { mutationDelayMs: 1_000 });
  await page.goto('/ensemble');
  await expect(page.getByRole('heading', { name: 'Concert Band' })).toBeVisible();

  await page.getByRole('button', { name: 'Join another class' }).click();
  await page.getByLabel('Class code').fill('chamber7');
  await page.getByLabel('Your instrument').selectOption('tuba');
  const joinButton = page.getByRole('button', { name: 'Join', exact: true });
  await joinButton.click();
  await expect(page.getByRole('button', { name: 'Joining class…' })).toBeDisabled();

  await expect(page.getByText(/You joined.*Chamber Winds/)).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Chamber Winds' })).toBeVisible();
  await expect(page.getByRole('tab', { name: 'Chamber Winds' })).toHaveClass(/active/);
  await expect(page.getByRole('tab', { name: 'Concert Band' })).toBeVisible();
  await expect(page.getByRole('tab', { name: 'Jazz Band' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Join another class' })).toHaveCount(0);
  expect(counters.joins).toBe(1);
  expect(counters.joinPayload).toEqual({
    code: 'CHAMBER7',
    instrument_id: 'tuba',
    sharing_consent: { scope_code: 'cloud_practice_sessions_since_membership_v1', acknowledged: true },
  });
});

test('a managing member can leave once while a slow request is in flight', async ({ page }) => {
  const counters = await installSignedInClassFixture(page, {
    mutationDelayMs: 200,
    initialGroups: [{
      id: 41,
      name: 'Admin Member Class',
      join_code: 'ADMIN41',
      director_user_id: 12,
      viewer_role: 'admin_observer',
      viewer_can_leave: true,
      viewer_can_manage: true,
      viewer_can_view_roster: true,
      viewer_can_view_class_analytics: true,
      viewer_has_aggregate_sharing_consent: false,
      roster_scope: 'full',
    }],
  });
  await page.goto('/ensemble');
  await expect(page.getByRole('heading', { name: 'Admin Member Class' })).toBeVisible();

  await page.getByRole('button', { name: 'Leave class' }).click();
  const dialog = page.getByRole('dialog', { name: 'Leave Admin Member Class?' });
  const confirmLeave = dialog.getByRole('button', { name: 'Leave class' });
  await confirmLeave.evaluate((button) => {
    (button as HTMLButtonElement).click();
    (button as HTMLButtonElement).click();
  });

  await expect(dialog).toHaveAttribute('aria-busy', 'true');
  await expect(dialog.getByRole('button', { name: 'Leaving…' })).toBeDisabled();
  await expect(dialog.getByRole('button', { name: 'Cancel' })).toBeDisabled();
  await expect(page.getByText(/You left.*Admin Member Class/)).toBeVisible();
  await expect(dialog).toBeHidden();
  await expect(page.getByRole('heading', { name: 'Join your class' })).toBeVisible();
  expect(counters.leaves).toBe(1);
});

test('remove-member confirmation is keyboard contained and submits once', async ({ page }) => {
  const counters = await installSignedInClassFixture(page, {
    mutationDelayMs: 200,
    initialGroups: [{
      id: 51,
      name: 'Roster Test',
      join_code: 'ROSTER51',
      director_user_id: 99,
      viewer_role: 'owner',
      viewer_can_leave: false,
      viewer_can_manage: true,
      viewer_can_view_roster: true,
      viewer_can_view_class_analytics: true,
      viewer_has_aggregate_sharing_consent: false,
      roster_scope: 'full',
    }],
    initialRoster: [{
      roster_row_id: 'roster-row-801',
      member_id: 801,
      user_id: 801,
      username: 'student-one',
      display_name: 'Student One',
      instrument_id: 'horn',
      status: 'active',
      role_in_group: 'student',
      sessions_count: 2,
      practice_minutes: 18,
      average_abs_cents: 7,
      in_tune_percentage: 82,
      last_practice_at: '2026-07-16T12:00:00Z',
      last_active_at: '2026-07-16T12:00:00Z',
      lifetime: { sessions_count: 2, practice_minutes: 18, average_abs_cents: 7, in_tune_percentage: 82, last_practice_at: '2026-07-16T12:00:00Z' },
      current_7d: { sessions_count: 1, practice_minutes: 8, average_abs_cents: 6, in_tune_percentage: 85, last_practice_at: '2026-07-16T12:00:00Z' },
      previous_7d: { sessions_count: 1, practice_minutes: 10, average_abs_cents: 8, in_tune_percentage: 79, last_practice_at: '2026-07-09T12:00:00Z' },
      delta: { sessions_count: 0, practice_minutes: -2, average_abs_cents: -2, in_tune_percentage: 6 },
      inactivity: { state: 'inactive_7d', days_since_last_practice: 39, last_practice_at: '2026-07-16T12:00:00Z' },
    }],
  });
  await page.goto('/ensemble');

  const trigger = page.getByRole('button', { name: 'Remove' });
  await trigger.click();
  let dialog = page.getByRole('dialog', { name: 'Remove Student One?' });
  await expect(dialog.getByRole('button', { name: 'Cancel' })).toBeFocused();
  await page.keyboard.press('Shift+Tab');
  await expect(dialog.getByRole('button', { name: 'Remove', exact: true })).toBeFocused();
  await page.keyboard.press('Tab');
  await expect(dialog.getByRole('button', { name: 'Cancel' })).toBeFocused();
  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
  await expect(trigger).toBeFocused();

  await trigger.click();
  dialog = page.getByRole('dialog', { name: 'Remove Student One?' });
  await dialog.getByRole('button', { name: 'Remove', exact: true }).evaluate((button) => {
    (button as HTMLButtonElement).click();
    (button as HTMLButtonElement).click();
  });
  await expect(dialog).toHaveAttribute('aria-busy', 'true');
  await expect(dialog.getByRole('button', { name: 'Removing…' })).toBeDisabled();
  await expect(dialog.getByRole('button', { name: 'Cancel' })).toBeDisabled();
  await expect(page.getByText('Student One removed.')).toBeVisible();
  await expect(dialog).toBeHidden();
  expect(counters.removes).toBe(1);
});

test('class mutations ignore duplicate and competing activations', async ({ page }) => {
  const counters = await installSignedInClassFixture(page, {
    mutationDelayMs: 150,
    invitations: [{
      member_id: 701,
      group_id: 1,
      group_name: 'Concert Band',
      instrument_id: 'unassigned',
      role_in_group: 'student',
      invited_at: '2026-07-13T12:00:00Z',
      director_name: 'Ms. Rivera',
    }],
  });
  await page.goto('/ensemble');
  await expect(page.getByRole('heading', { name: 'Concert Band' })).toBeVisible();

  await expect(page.getByRole('button', { name: 'Accept' })).toBeDisabled();
  await expect(page.getByText('Choose your instrument before accepting.')).toBeVisible();
  await page.getByLabel('Your instrument').first().selectOption('horn');

  await page.evaluate(() => {
    const buttons = Array.from(document.querySelectorAll('button'));
    buttons.find((button) => button.textContent?.trim() === 'Accept')?.click();
    buttons.find((button) => button.textContent?.trim() === 'Decline')?.click();
  });
  await expect(page.getByRole('button', { name: 'Joining class…' })).toBeDisabled();
  await expect(page.getByText(/You joined.*Concert Band/)).toBeVisible();
  expect(counters.accepts + counters.declines).toBe(1);
  expect(counters.accepts).toBe(1);

  await page.getByRole('button', { name: 'New class' }).click();
  await page.getByLabel('New class name').fill('Morning Brass');
  const createButton = page.getByRole('button', { name: 'Create a class' });
  await createButton.evaluate((button) => {
    (button as HTMLButtonElement).click();
    (button as HTMLButtonElement).click();
  });
  await expect(page.getByRole('button', { name: 'Creating…' })).toBeDisabled();
  await expect(page.getByText(/Morning Brass.*is ready/)).toBeVisible();
  expect(counters.creates).toBe(1);

  await page.getByLabel('Add a student by username').fill('student-two');
  const inviteButton = page.getByRole('button', { name: 'Send invite' });
  await inviteButton.evaluate((button) => {
    (button as HTMLButtonElement).click();
    (button as HTMLButtonElement).click();
  });
  await expect(page.getByRole('button', { name: 'Sending…' })).toBeDisabled();
  await expect(page.getByText(/Invite sent/)).toBeVisible();
  expect(counters.memberInvites).toBe(1);
});
