import { expect, test, type Page, type Route } from 'playwright/test';

type Group = {
  id: number;
  name: string;
  join_code?: string | null;
  viewer_role: string;
  viewer_can_leave: boolean;
  viewer_can_manage: boolean;
};

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

async function installSignedInClassFixture(page: Page) {
  let groups: Group[] = [
    { id: 1, name: 'Concert Band', viewer_role: 'student', viewer_can_leave: true, viewer_can_manage: false },
    { id: 2, name: 'Jazz Band', viewer_role: 'assistant', viewer_can_leave: true, viewer_can_manage: false },
    { id: 3, name: 'Student-led Brass', join_code: null, viewer_role: 'owner', viewer_can_leave: false, viewer_can_manage: true },
  ];

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
    if (path === '/api/ensemble/invitations') return respond({ invitations: [] });
    if (path === '/api/ensemble/groups' && request.method() === 'GET') return respond(groups);

    const rotateMatch = path.match(/^\/api\/ensemble\/groups\/(\d+)\/join-code\/rotate$/);
    if (rotateMatch && request.method() === 'POST') {
      const groupID = Number(rotateMatch[1]);
      groups = groups.map((group) => group.id === groupID ? { ...group, join_code: 'ABCD2345' } : group);
      return respond({ group_id: groupID, join_code: 'ABCD2345' });
    }

    const leaveMatch = path.match(/^\/api\/ensemble\/groups\/(\d+)\/membership$/);
    if (leaveMatch && request.method() === 'DELETE') {
      const groupID = Number(leaveMatch[1]);
      groups = groups.filter((group) => group.id !== groupID);
      return respond({ left: true, group_id: groupID });
    }

    const groupMatch = path.match(/^\/api\/ensemble\/groups\/(\d+)$/);
    if (groupMatch && request.method() === 'GET') {
      const group = groups.find((candidate) => candidate.id === Number(groupMatch[1]));
      if (!group) return respond({ detail: 'Group not found' }, 404);
      return respond({
        ...group,
        roster_scope: group.viewer_can_manage ? 'full' : 'self',
        members: group.viewer_can_manage ? [] : [{
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
}

test('class UI stays stable across switching and leaving one of several classes', async ({ page }) => {
  await installSignedInClassFixture(page);
  await page.goto('/ensemble');

  await expect(page.getByRole('heading', { name: 'Join another class' })).toBeVisible();
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
  await expect(page.getByText('You left “Jazz Band”.')).toBeVisible();
  await expect(page.getByRole('button', { name: 'Jazz Band' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Concert Band' })).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Join another class' })).toBeVisible();

  await page.getByRole('button', { name: 'Student-led Brass' }).click();
  await expect(page.getByText('Unavailable', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Copy code' })).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Share link' })).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Leave class' })).toHaveCount(0);
  await page.getByRole('button', { name: 'Create code' }).click();
  await expect(page.getByText('ABCD2345', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Rotate code' })).toBeVisible();

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
