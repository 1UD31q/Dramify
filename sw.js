// sw.js — Service Worker для Dramify
// Отвечает за локальные уведомления о начале и конце смены

const CACHE_NAME = 'dramify-v1';

self.addEventListener('install', e => {
  self.skipWaiting();
});

self.addEventListener('activate', e => {
  e.waitUntil(self.clients.claim());
});

// Получаем сообщение от страницы с расписанием уведомлений
self.addEventListener('message', e => {
  if (e.data && e.data.type === 'SCHEDULE_NOTIFICATIONS') {
    scheduleAll(e.data.notifications);
  }
  if (e.data && e.data.type === 'CANCEL_NOTIFICATIONS') {
    cancelAll();
  }
});

// Хранилище таймеров (в памяти SW)
let timers = [];

function cancelAll() {
  timers.forEach(t => clearTimeout(t));
  timers = [];
}

function scheduleAll(notifications) {
  cancelAll();
  const now = Date.now();

  notifications.forEach(n => {
    const delay = n.fireAt - now;
    if (delay <= 0) return; // уже прошло — пропускаем
    if (delay > 24 * 60 * 60 * 1000) return; // больше суток — SW не доживёт

    const t = setTimeout(() => {
      self.registration.showNotification(n.title, {
        body: n.body,
        icon: '/favicon.png',
        badge: '/favicon.png',
        tag: n.tag,           // не дублировать, если уже показано
        renotify: false,
        vibrate: [200, 100, 200],
        data: { url: self.registration.scope }
      });
    }, delay);

    timers.push(t);
  });
}

// Клик по уведомлению — открываем приложение
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const target = (e.notification.data && e.notification.data.url) || self.registration.scope;
  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(clients => {
      for (const c of clients) {
        if (c.url.startsWith(self.registration.scope) && 'focus' in c) {
          return c.focus();
        }
      }
      if (self.clients.openWindow) return self.clients.openWindow(target);
    })
  );
});
