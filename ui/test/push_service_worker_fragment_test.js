const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

function loadWorkerFragment() {
  const fragmentPath = path.join(
    __dirname,
    '..',
    'web',
    'push_service_worker_fragment.js',
  );
  const source = fs.readFileSync(fragmentPath, 'utf8');
  const context = {
    URL,
    Number,
    self: {
      location: {
        origin: 'https://app.example.test',
      },
      addEventListener() {},
      clients: {
        matchAll: async () => [],
        openWindow: async () => null,
      },
      registration: {
        showNotification: async () => null,
      },
      skipWaiting() {},
    },
  };

  vm.runInNewContext(source, context, { filename: fragmentPath });
  return context;
}

function createClient(url, options = {}) {
  const client = {
    url,
    focused: options.focused === true,
    visibilityState: options.visibilityState || 'hidden',
    focusCalls: 0,
    navigatedTo: [],
    async focus() {
      this.focusCalls += 1;
      return this;
    },
    async navigate(targetUrl) {
      this.navigatedTo.push(targetUrl);
      this.url = targetUrl;
      return options.navigateReturnsNull === true ? null : this;
    },
  };
  return client;
}

test('selectBestClient prefers the client already showing the target room', () => {
  const context = loadWorkerFragment();
  const targetUrl = new URL(
    '/rooms?open_room=42',
    context.self.location.origin,
  );
  const clients = [
    createClient('https://app.example.test/'),
    createClient('https://app.example.test/rooms', {
      focused: true,
      visibilityState: 'visible',
    }),
    createClient('https://app.example.test/rooms?open_room=42'),
  ];

  const bestClient = context.selectBestClient(clients, targetUrl, 42);

  assert.equal(bestClient, clients[2]);
});

test('focusNotificationTarget navigates the best matching rooms client', async () => {
  const context = loadWorkerFragment();
  const targetUrl = new URL(
    '/rooms?open_room=42',
    context.self.location.origin,
  );
  const genericClient = createClient('https://app.example.test/');
  const roomsClient = createClient('https://app.example.test/rooms', {
    visibilityState: 'visible',
  });

  context.self.clients.matchAll = async () => [genericClient, roomsClient];

  await context.focusNotificationTarget(targetUrl, { room_id: 42 });

  assert.deepEqual(roomsClient.navigatedTo, [targetUrl.href]);
  assert.equal(roomsClient.focusCalls, 1);
  assert.deepEqual(genericClient.navigatedTo, []);
});

test('focusNotificationTarget opens a new window when no same-origin client exists', async () => {
  const context = loadWorkerFragment();
  const targetUrl = new URL(
    '/rooms?open_room=42',
    context.self.location.origin,
  );
  const externalClient = createClient('https://other.example.test/rooms');
  const opened = [];

  context.self.clients.matchAll = async () => [externalClient];
  context.self.clients.openWindow = async (url) => {
    opened.push(url);
    return null;
  };

  await context.focusNotificationTarget(targetUrl, { room_id: 42 });

  assert.deepEqual(opened, [targetUrl.href]);
  assert.equal(externalClient.focusCalls, 0);
});
