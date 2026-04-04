
const NARLUN_DEFAULT_NOTIFICATION = {
  title: 'Narlun',
  body: '',
  tag: 'narlun',
  icon: '/icons/Icon-192.png',
  badge: '/icons/Icon-maskable-192.png',
  data: {},
};

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
  const targetUrl = new URL(data.url || '/rooms', self.location.origin).href;

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(
      (clients) => {
        for (const client of clients) {
          if (new URL(client.url).origin !== self.location.origin) {
            continue;
          }
          return client.navigate(targetUrl).then(() => client.focus());
        }
        return self.clients.openWindow(targetUrl);
      },
    ),
  );
});
