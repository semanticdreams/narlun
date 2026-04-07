
const NARLUN_DEFAULT_NOTIFICATION = {
  title: 'narlun',
  body: '',
  tag: 'narlun',
  icon: '/icons/Icon-192.png',
  badge: '/icons/Icon-maskable-192.png',
  data: {},
};

function parseNarlunUrl(value) {
  try {
    return new URL(value || '/', self.location.origin);
  } catch (_) {
    return null;
  }
}

function parseRoomId(value) {
  const parsed = Number.parseInt(String(value || ''), 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function clientMatchScore(client, targetUrl, roomId) {
  const clientUrl = parseNarlunUrl(client.url);
  if (!clientUrl || clientUrl.origin !== self.location.origin) {
    return -1;
  }

  let score = 0;
  if (clientUrl.href === targetUrl.href) {
    score += 1000;
  }
  if (clientUrl.pathname === targetUrl.pathname) {
    score += 100;
  }
  if (clientUrl.search === targetUrl.search) {
    score += 50;
  }

  if (targetUrl.pathname === '/rooms' && clientUrl.pathname === '/rooms') {
    score += 10;
    if (roomId !== null && parseRoomId(clientUrl.searchParams.get('open_room')) === roomId) {
      score += 900;
    }
  }

  if (client.focused) {
    score += 5;
  }
  if (client.visibilityState === 'visible') {
    score += 3;
  }
  return score;
}

function selectBestClient(clients, targetUrl, roomId) {
  let bestClient = null;
  let bestScore = -1;

  for (const client of clients) {
    const score = clientMatchScore(client, targetUrl, roomId);
    if (score > bestScore) {
      bestClient = client;
      bestScore = score;
    }
  }

  return bestClient;
}

async function focusNotificationTarget(targetUrl, data) {
  const clients = await self.clients.matchAll({
    type: 'window',
    includeUncontrolled: true,
  });
  const roomId = parseRoomId(data && data.room_id);
  const bestClient = selectBestClient(clients, targetUrl, roomId);

  if (!bestClient) {
    return self.clients.openWindow(targetUrl.href);
  }

  const currentUrl = parseNarlunUrl(bestClient.url);
  if (currentUrl && currentUrl.href === targetUrl.href) {
    return bestClient.focus();
  }

  if (typeof bestClient.navigate === 'function') {
    const navigatedClient = await bestClient.navigate(targetUrl.href);
    return (navigatedClient || bestClient).focus();
  }

  return bestClient.focus();
}

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
});

self.addEventListener('push', (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    payload = {};
  }

  const notification = Object.assign(
    {},
    NARLUN_DEFAULT_NOTIFICATION,
    payload.notification || {},
  );
  event.waitUntil(
    self.registration.showNotification(notification.title, {
      body: notification.body,
      tag: notification.tag,
      icon: notification.icon,
      badge: notification.badge,
      data: notification.data || {},
      renotify: notification.renotify === true,
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const targetUrl = parseNarlunUrl(data.url || '/rooms');

  if (!targetUrl) {
    return;
  }

  event.waitUntil(focusNotificationTarget(targetUrl, data));
});
