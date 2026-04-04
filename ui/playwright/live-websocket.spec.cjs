const { test, expect } = require('@playwright/test');

const {
  BackendClient,
  LiveHarness,
  randomUsername,
} = require('./support/live-harness.cjs');
const {
  dispatchInstallPrompt,
  installPromptCallCount,
} = require('./support/install-prompt.cjs');

let harness;
let backendClient;

async function browserSignup(page, rootUrl, username) {
  await page.goto(`${rootUrl}/`);
  await expect(
    page.getByText('Choose a username to start instantly.'),
  ).toBeVisible({ timeout: 20_000 });
  await page.locator('input:not([disabled])').first().fill(username);
  await page.getByRole('button', { name: 'Sign Up' }).click();
  await expect(page.getByRole('tab', { name: 'Nearby' })).toBeVisible();
  await expect(page.getByRole('tab', { name: 'Rooms' })).toBeVisible();

  const currentUser = await currentBrowserUser(page);
  expect(currentUser.authenticated).toBe(true);
}

async function currentBrowserUser(page) {
  return page.evaluate(async () => {
    const response = await fetch('/api/users/me', { credentials: 'include' });
    return response.json();
  });
}

async function currentJwtCookie(page) {
  const cookies = await page.context().cookies();
  const jwtCookie = cookies.find((cookie) => cookie.name === 'jwt');
  if (!jwtCookie) {
    throw new Error('Browser JWT cookie is missing');
  }
  return `jwt=${jwtCookie.value}`;
}

test.beforeEach(async ({ page }) => {
  harness = new LiveHarness();
  await harness.start();
  backendClient = new BackendClient(harness.apiUrl);
  await page.context().clearCookies();
  await page.context().grantPermissions(['geolocation'], {
    origin: harness.rootUrl,
  });
  await page.context().setGeolocation({ latitude: 1, longitude: 2 });
  await page.addInitScript(() => {
    window.localStorage.clear();
  });
  await page.goto(harness.rootUrl);
});

test.afterEach(async () => {
  await harness.close();
});

test('rooms list updates and live messages arrive from the backend in the browser', async ({ page }) => {
  await browserSignup(page, harness.rootUrl, randomUsername('alice'));
  const alice = await currentBrowserUser(page);
  const bob = await backendClient.signupGuest(randomUsername('bob'));
  const room = await bob.joinUser(alice.id);

  await page.getByRole('tab', { name: 'Rooms' }).click();
  await expect(page.getByText(bob.username)).toBeVisible();
  await page.getByText(bob.username).last().click();
  await bob.sendMessage(room.id, 'hello from backend');
  await expect(page.getByText('hello from backend')).toBeVisible();
});

test('tapping a nearby user opens the room immediately in the browser', async ({ page }) => {
  await browserSignup(page, harness.rootUrl, randomUsername('alice'));
  const bob = await backendClient.signupGuest(randomUsername('bob'));

  await bob.checkin(1, 2);
  await page.reload();

  await expect(page.getByText(bob.username)).toBeVisible({ timeout: 20_000 });
  await page.getByText(bob.username).click();

  await expect(page.getByRole('textbox')).toBeVisible();
  await expect(page.getByText(bob.username).first()).toBeVisible();
});

test('room deletion while open returns to the room list in the browser', async ({ page }) => {
  await browserSignup(page, harness.rootUrl, randomUsername('alice'));
  const alice = await currentBrowserUser(page);
  const bob = await backendClient.signupGuest(randomUsername('bob'));

  await bob.joinUser(alice.id);
  await page.getByRole('tab', { name: 'Rooms' }).click();
  await expect(page.getByText(bob.username)).toBeVisible();
  await page.getByText(bob.username).last().click();

  await bob.signout();

  await expect(page.getByText('This room is no longer available.').first()).toBeVisible();
  await expect(page.getByRole('tab', { name: 'Rooms' })).toBeVisible();
  await expect(page.getByText(bob.username)).toHaveCount(0);
});

test('guest account signout from another client returns the browser app to signup', async ({ page }) => {
  await browserSignup(page, harness.rootUrl, randomUsername('alice'));
  const browserJwt = await currentJwtCookie(page);

  await backendClient.signout(browserJwt);

  await expect(page.getByText('Choose a username to start instantly.')).toBeVisible();
  await expect(page.getByText('Sign Up')).toBeVisible();
});

test('rooms list websocket reconnect survives a backend restart in the browser', async ({ page }) => {
  await browserSignup(page, harness.rootUrl, randomUsername('alice'));
  const alice = await currentBrowserUser(page);

  await harness.restartBackend();

  const bob = await backendClient.signupGuest(randomUsername('bob'));
  await bob.joinUser(alice.id);

  await page.getByRole('tab', { name: 'Rooms' }).click();
  await expect(page.getByText(bob.username)).toBeVisible({ timeout: 20_000 });
});

test('room websocket reconnect survives a backend restart in the browser', async ({ page }) => {
  await browserSignup(page, harness.rootUrl, randomUsername('alice'));
  const alice = await currentBrowserUser(page);
  const bob = await backendClient.signupGuest(randomUsername('bob'));
  const room = await bob.joinUser(alice.id);

  await page.getByRole('tab', { name: 'Rooms' }).click();
  await expect(page.getByText(bob.username)).toBeVisible();
  await page.getByText(bob.username).last().click();

  await harness.restartBackend();

  await bob.sendMessage(room.id, 'message after restart');
  await expect(page.getByText('message after restart')).toBeVisible({ timeout: 20_000 });
});

test('install prompt can be triggered from the profile screen', async ({ page }) => {
  const username = randomUsername('alice');
  await expect(
    page.getByText('Choose a username to start instantly.'),
  ).toBeVisible({ timeout: 20_000 });
  await dispatchInstallPrompt(page);
  await page.locator('input:not([disabled])').first().fill(username);
  await page.getByRole('button', { name: 'Sign Up' }).click();
  await expect(page.getByRole('tab', { name: 'Nearby' })).toBeVisible();

  await page.getByRole('button', { name: 'Account menu' }).click();
  await page.getByRole('menuitem', { name: 'Profile' }).click();
  await expect(page.getByText('Profile')).toBeVisible();
  await page.getByRole('button', { name: 'Install app' }).click();

  await expect(page.getByText('Narlun is installing.').first()).toBeVisible();
  expect(await installPromptCallCount(page)).toBe(1);
});

test('home invite link sends a new user through signup into a direct room', async ({ browser, page }) => {
  await browserSignup(page, harness.rootUrl, randomUsername('alice'));
  const alice = await currentBrowserUser(page);
  const browserJwt = await currentJwtCookie(page);

  await page.getByRole('button', { name: 'Invite someone' }).click();
  await expect(page.getByRole('heading', { name: 'Invite someone' })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Copy link' })).toBeVisible();
  const invite = await backendClient.createInvite(browserJwt);
  const inviteLink = `${harness.rootUrl}/invite/${invite.token}`;

  const inviteeContext = await browser.newContext();
  const inviteePage = await inviteeContext.newPage();
  try {
    await inviteePage.goto(inviteLink);
    await expect(
      inviteePage.getByText('Choose a username to start instantly.'),
    ).toBeVisible({ timeout: 20_000 });

    const inviteeUsername = randomUsername('guest');
    await inviteePage.locator('input:not([disabled])').first().fill(inviteeUsername);
    await inviteePage.getByRole('button', { name: 'Sign Up' }).click();

    await expect(inviteePage.getByRole('textbox')).toBeVisible({ timeout: 20_000 });
    await expect(inviteePage.getByText(alice.username).first()).toBeVisible();

    await page.getByRole('button', { name: 'Back' }).click();
    await page.getByRole('tab', { name: 'Rooms' }).click();
    await expect(page.getByText(inviteeUsername)).toBeVisible({ timeout: 20_000 });
  } finally {
    await inviteeContext.close();
  }
});

test('room invite link sends a new user through signup into the existing room', async ({ browser, page }) => {
  await browserSignup(page, harness.rootUrl, randomUsername('alice'));
  const alice = await currentBrowserUser(page);
  const browserJwt = await currentJwtCookie(page);
  const bob = await backendClient.signupGuest(randomUsername('bob'));
  const room = await bob.joinUser(alice.id);

  await page.getByRole('tab', { name: 'Rooms' }).click();
  await expect(page.getByText(bob.username)).toBeVisible();
  await page.getByText(bob.username).last().click();
  await expect(page.getByRole('textbox')).toBeVisible();

  await page.getByRole('button', { name: 'Invite people to this room' }).click();
  await expect(page.getByRole('heading', { name: /Invite to/ })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Copy link' })).toBeVisible();
  const invite = await backendClient.createInvite(browserJwt, room.id);
  const inviteLink = `${harness.rootUrl}/invite/${invite.token}`;

  const inviteeContext = await browser.newContext();
  const inviteePage = await inviteeContext.newPage();
  try {
    await inviteePage.goto(inviteLink);
    await expect(
      inviteePage.getByText('Choose a username to start instantly.'),
    ).toBeVisible({ timeout: 20_000 });

    await inviteePage.locator('input:not([disabled])').first().fill(randomUsername('charlie'));
    await inviteePage.getByRole('button', { name: 'Sign Up' }).click();

    await expect(inviteePage.getByRole('textbox')).toBeVisible({ timeout: 20_000 });
    await bob.sendMessage(room.id, 'welcome to the room');
    await expect(inviteePage.getByText('welcome to the room')).toBeVisible({ timeout: 20_000 });
  } finally {
    await inviteeContext.close();
  }
});
