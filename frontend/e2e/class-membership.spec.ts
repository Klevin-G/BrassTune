import { expect, test, type Page, type Route } from 'playwright/test';

type Group = {
  id: number;
  name: string;
  join_code?: string | null;
  director_user_id?: number | null;
  viewer_role: string;
  viewer_can_leave?: boolean;
  viewer_can_manage?: boolean;
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

type FixtureOptions = {
  groupDelaysMs?: Record<number, number>;
  mutationDelayMs?: number;
  invitations?: Invitation[];
  initialGroups?: Group[];
};

const delay = (milliseconds: number) => new Promise((resolve) => setTimeout(resolve, milliseconds));

const fakeAuthModule = `
const session = { access_token: 'signed-in-e2e-token', user: { id: 'class-user' } };
export const supabaseConfigured = true;
export const authProviders = { google: false, apple: false };
export const supabase = {
  auth: {
    getSession: async () => ({ data: { session } }),
    onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
    signOut: async () => ({ error: null }),
    signInWithPassword: async () => ({ data: { session }, error: null }),
    signUp: async () => ({ data: { session }, error: null }),
  },
};
`;

async function installSignedInClassFixture(page: Page, options: FixtureOptions = {}) {
  let groups: Group[] = options.initialGroups ? [...options.initialGroups] : [
    { id: 1, name: 'Concert Band', director_user_id: 12, viewer_role: 'student' },
    { id: 2, name: 'Jazz Band', viewer_role: 'assistant', viewer_can_leave: true, viewer_can_manage: false },
    { id: 3, name: 'Student-led Brass', join_code: null, viewer_role: 'owner', viewer_can_leave: false, viewer_can_manage: true },
    { id: 4, name: 'Legacy-owned Brass', join_code: 'LEGACY99', director_user_id: 99, viewer_role: 'owner' },
  ];
  let invitations = [...(options.invitations ?? [])];
  const counters = {
    creates: 0,
    memberInvites: 0,
    accepts: 0,
    declines: 0,
    joins: 0,
    leaves: 0,
    joinPayload: null as { code?: string; instrument_id?: string } | null,
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

    if (path === '/api/instruments') return respond([]);
    if (path === '/api/users/current') {
      return respond({
        id: 99,
        supabase_user_id: 'class-user',
        username: 'student99',
        display_name: 'Class Student',
        email: 'student@example.test',
        role: 'director',
        primary_instrument_id: 'horn',
      });
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

    const groupMatch = path.match(/^\/api\/ensemble\/groups\/(\d+)$/);
    if (groupMatch && request.method() === 'GET') {
      const groupID = Number(groupMatch[1]);
      const groupDelay = options.groupDelaysMs?.[groupID] ?? 0;
      if (groupDelay) await delay(groupDelay);
      const group = groups.find((candidate) => candidate.id === groupID);
      if (!group) return respond({ detail: 'Group not found' }, 404);
      const canManage = group.viewer_can_manage ?? group.director_user_id === 99;
      return respond({
        ...group,
        roster_scope: canManage ? 'full' : 'self',
        members: canManage ? [] : [{
          id: group.id * 10,
          group_id: group.id,
          instrument_id: 'horn',
          role_in_group: group.viewer_role,
          status: 'active',
          display_name: 'You',
          is_current_user: true,
        }],
      });
    }

    if (/^\/api\/ensemble\/groups\/\d+\/roster$/.test(path)) return respond({ students: [] });
    if (path === '/api/ensemble/summary') return respond({ sections: [] });
    if (path === '/api/ensemble/report') return respond({});
    return respond({ detail: 'Unexpected class fixture request' }, 500);
  });

  await page.addInitScript(() => {
    localStorage.setItem('brasstune.onboardingComplete', 'true');
    localStorage.setItem('brasstune.instrument', 'horn');
    localStorage.setItem('brasstune.referencePitch', '442');
    localStorage.setItem('brasstune.guestSessions.v1', JSON.stringify([{ id: -901, name: 'Local warmup' }]));
  });

  return counters;
}

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
  await expect(page.getByRole('button', { name: 'Concert Band' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Jazz Band' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Leave class' })).toBeVisible();

  await page.getByRole('button', { name: 'Jazz Band' }).click();
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
  await expect(page.getByRole('button', { name: 'Jazz Band' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Concert Band' })).toBeVisible();
  await expect(joinAnother).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Join another class' })).toHaveCount(0);

  await page.getByRole('button', { name: 'Student-led Brass' }).click();
  await expect(page.getByText('Unavailable', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Copy code' })).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Share link' })).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Leave class' })).toHaveCount(0);
  await page.getByRole('button', { name: 'Create code' }).click();
  await expect(page.getByText('ABCD2345', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Rotate code' })).toBeVisible();

  await page.getByRole('button', { name: 'Legacy-owned Brass' }).click();
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

  const concertTab = page.getByRole('button', { name: 'Concert Band' });
  const jazzTab = page.getByRole('button', { name: 'Jazz Band' });
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
  await expect(page.getByRole('button', { name: 'Joining…' })).toBeDisabled();

  await expect(page.getByText(/You joined.*Chamber Winds/)).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Chamber Winds' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Chamber Winds' })).toHaveClass(/active/);
  await expect(page.getByRole('button', { name: 'Concert Band' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Jazz Band' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Join another class' })).toHaveCount(0);
  expect(counters.joins).toBe(1);
  expect(counters.joinPayload).toEqual({ code: 'CHAMBER7', instrument_id: 'tuba' });
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

test('class mutations ignore duplicate and competing activations', async ({ page }) => {
  const counters = await installSignedInClassFixture(page, {
    mutationDelayMs: 150,
    invitations: [{
      member_id: 701,
      group_id: 1,
      group_name: 'Concert Band',
      instrument_id: 'horn',
      role_in_group: 'student',
      invited_at: '2026-07-13T12:00:00Z',
      director_name: 'Ms. Rivera',
    }],
  });
  await page.goto('/ensemble');
  await expect(page.getByRole('heading', { name: 'Concert Band' })).toBeVisible();

  await page.evaluate(() => {
    const buttons = Array.from(document.querySelectorAll('button'));
    buttons.find((button) => button.textContent?.trim() === 'Accept')?.click();
    buttons.find((button) => button.textContent?.trim() === 'Decline')?.click();
  });
  await expect(page.getByRole('button', { name: 'Joining…' })).toBeDisabled();
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
